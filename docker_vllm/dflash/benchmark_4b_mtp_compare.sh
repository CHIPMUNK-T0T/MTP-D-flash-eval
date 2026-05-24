#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_ROOT="${RESULTS_ROOT:-$ROOT_DIR/results}"
OUT_DIR="${OUT_DIR:-$RESULTS_ROOT/d-flash}"
LOG_DIR="${LOG_DIR:-$RESULTS_ROOT/logs/d-flash}"
METRICS_DIR="${METRICS_DIR:-$RESULTS_ROOT/metrics/d-flash}"
DRY_RUN="${1:-}"

EXISTING_SUMMARY_CSV="$OUT_DIR/summary.csv"
MTP_REQUESTS_CSV="$OUT_DIR/mtp_requests.csv"
MTP_SUMMARY_CSV="$OUT_DIR/mtp_summary.csv"
SPEC_COMPARE_CSV="$OUT_DIR/spec_compare.csv"
SPEC_COMPARE_MD="$OUT_DIR/spec_compare.md"
LOCK_DIR="$OUT_DIR/.mtp_compare.lock"

CONFIG_ID="MTP-FP8-n3"
LABEL="FP8 MTP n=3"
QUANT="fp8"
SPEC_METHOD="mtp"
NUM_SPECULATIVE_TOKENS="${NUM_SPECULATIVE_TOKENS:-3}"
MODEL="RedHatAI/Qwen3.5-4B-FP8-dynamic"
SCRIPT_NAME="qwen35-4b-fp8-mtp-n3.sh"

MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-4096}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-2048}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.937}"

PROMPT_DIR="${PROMPT_DIR:-$SCRIPT_DIR/../prompts}"
WORKLOADS=(
  "medium|256|$PROMPT_DIR/medium.txt"
  "long|512|$PROMPT_DIR/long.txt"
)

stop_server() {
  docker stop vllm-server >/dev/null 2>&1 || true
  docker rm vllm-server >/dev/null 2>&1 || true
}

acquire_lock() {
  mkdir -p "$OUT_DIR"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "another benchmark_4b_mtp_compare.sh run appears to be active: $LOCK_DIR" >&2
    exit 1
  fi
  trap 'stop_server; rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
}

init_output_files() {
  if [ ! -f "$EXISTING_SUMMARY_CSV" ]; then
    echo "missing existing D-Flash summary: $EXISTING_SUMMARY_CSV" >&2
    exit 1
  fi

  mkdir -p "$OUT_DIR/responses" "$LOG_DIR" "$METRICS_DIR"
  rm -rf "$OUT_DIR/responses/${CONFIG_ID}_medium" "$OUT_DIR/responses/${CONFIG_ID}_long"
  rm -f "$LOG_DIR/${CONFIG_ID}_startup.log"
  rm -f "$METRICS_DIR/${CONFIG_ID}_"*.prom
  rm -f "$MTP_REQUESTS_CSV" "$MTP_SUMMARY_CSV" "$SPEC_COMPARE_CSV" "$SPEC_COMPARE_MD"

  cat > "$MTP_REQUESTS_CSV" <<'EOF'
config_id,label,quantization,spec_method,num_speculative_tokens,workload,max_tokens,run_index,elapsed_ms,completion_tokens,tok_per_s,status
EOF

  cat > "$MTP_SUMMARY_CSV" <<'EOF'
config_id,label,quantization,spec_method,num_speculative_tokens,workload,max_tokens,max_num_batched_tokens,status,median_elapsed_ms,median_tok_per_s,draft_tokens,accepted_tokens,acceptance_rate,startup_seconds,notes
EOF
}

build_payload() {
  local model="$1"
  local prompt_file="$2"
  local max_tokens="$3"
  python3 - "$model" "$prompt_file" "$max_tokens" <<'PY'
import json
import sys

model, prompt_file, max_tokens = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(prompt_file, encoding="utf-8") as f:
    prompt = f.read()
print(json.dumps({
    "model": model,
    "messages": [
        {
            "role": "user",
            "content": prompt,
        }
    ],
    "max_tokens": max_tokens,
    "temperature": 0,
    "chat_template_kwargs": {
        "enable_thinking": False,
    },
}, ensure_ascii=False))
PY
}

extract_response_field() {
  local response_file="$1"
  local field="$2"
  python3 - "$response_file" "$field" <<'PY'
import json
import sys

path, field = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    data = json.load(f)

if "error" in data:
    raise SystemExit(data["error"])

if field == "completion_tokens":
    print(data.get("usage", {}).get("completion_tokens", 0))
elif field == "text":
    choices = data.get("choices", [])
    if not choices:
        print("")
    else:
        choice = choices[0]
        message = choice.get("message", {})
        print(message.get("content", choice.get("text", "")) or "")
else:
    raise SystemExit(f"unsupported field: {field}")
PY
}

metric_value() {
  local metric_file="$1"
  local needle="$2"
  python3 - "$metric_file" "$needle" <<'PY'
import sys

path, needle = sys.argv[1], sys.argv[2]
value = 0.0
try:
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("#") or needle not in line:
                continue
            try:
                value += float(line.strip().split()[-1])
            except (IndexError, ValueError):
                pass
except FileNotFoundError:
    pass
print(value)
PY
}

median_from_list() {
  python3 - "$@" <<'PY'
import sys

values = [float(v) for v in sys.argv[1:] if v != ""]
if not values:
    print("")
    raise SystemExit
values.sort()
mid = len(values) // 2
if len(values) % 2:
    print(f"{values[mid]:.4f}")
else:
    print(f"{(values[mid - 1] + values[mid]) / 2:.4f}")
PY
}

format_rate() {
  python3 - "$1" "$2" <<'PY'
import sys

accepted = float(sys.argv[1])
draft = float(sys.argv[2])
print("" if draft <= 0 else f"{accepted / draft:.4f}")
PY
}

wait_for_startup() {
  local startup_log="$1"
  local timeout=900
  local elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    docker logs vllm-server >"$startup_log" 2>&1 || true
    if grep -q "startup complete" "$startup_log"; then
      echo "$elapsed"
      return 0
    fi
    if grep -qE "RuntimeError|OutOfMemoryError|Engine core initialization failed|OOM|No available memory" "$startup_log"; then
      echo "$elapsed"
      return 1
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  echo "$elapsed"
  return 1
}

run_workload() {
  local workload="$1"
  local max_tokens="$2"
  local prompt_file="$3"
  local startup_seconds="$4"

  local payload
  payload="$(build_payload "$MODEL" "$prompt_file" "$max_tokens")"

  local response_dir="$OUT_DIR/responses/${CONFIG_ID}_${workload}"
  mkdir -p "$response_dir"

  local warmup_json="$response_dir/warmup.json"
  if ! curl -s --max-time 420 http://localhost:8000/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "$payload" >"$warmup_json"; then
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$CONFIG_ID" "$LABEL" "$QUANT" "$SPEC_METHOD" "$NUM_SPECULATIVE_TOKENS" \
      "$workload" "$max_tokens" "$MAX_NUM_BATCHED_TOKENS" "warmup_failed" \
      "" "" "" "" "" "$startup_seconds" "warmup_curl_failed" >>"$MTP_SUMMARY_CSV"
    return 0
  fi

  local metrics_before="$METRICS_DIR/${CONFIG_ID}_${workload}_before.prom"
  local metrics_after="$METRICS_DIR/${CONFIG_ID}_${workload}_after.prom"
  curl -s http://localhost:8000/metrics >"$metrics_before"

  local elapsed_values=()
  local tps_values=()
  local run_status="ok"
  local run_notes=""

  for run_index in 1 2 3 4 5; do
    local response_json="$response_dir/run${run_index}.json"
    local response_txt="$response_dir/run${run_index}.txt"
    local start_ms
    local end_ms
    local elapsed_ms
    start_ms="$(date +%s%3N)"
    if ! curl -s --max-time 420 http://localhost:8000/v1/chat/completions \
      -H "Content-Type: application/json" \
      -d "$payload" >"$response_json"; then
      run_status="request_failed"
      run_notes="run${run_index}_curl_failed"
      break
    fi
    end_ms="$(date +%s%3N)"
    elapsed_ms=$((end_ms - start_ms))

    local completion_tokens
    if ! completion_tokens="$(extract_response_field "$response_json" completion_tokens 2>/dev/null)"; then
      run_status="request_failed"
      run_notes="run${run_index}_parse_failed"
      break
    fi
    if ! extract_response_field "$response_json" text >"$response_txt" 2>/dev/null; then
      run_status="request_failed"
      run_notes="run${run_index}_text_failed"
      break
    fi

    local tok_per_s
    tok_per_s="$(python3 - "$completion_tokens" "$elapsed_ms" <<'PY'
import sys
tokens = float(sys.argv[1])
elapsed_ms = float(sys.argv[2])
print(f"{tokens / (elapsed_ms / 1000):.4f}")
PY
)"

    elapsed_values+=("$elapsed_ms")
    tps_values+=("$tok_per_s")

    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$CONFIG_ID" "$LABEL" "$QUANT" "$SPEC_METHOD" "$NUM_SPECULATIVE_TOKENS" \
      "$workload" "$max_tokens" "$run_index" "$elapsed_ms" "$completion_tokens" \
      "$tok_per_s" "ok" >>"$MTP_REQUESTS_CSV"
  done

  curl -s http://localhost:8000/metrics >"$metrics_after"

  if [ "$run_status" != "ok" ]; then
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$CONFIG_ID" "$LABEL" "$QUANT" "$SPEC_METHOD" "$NUM_SPECULATIVE_TOKENS" \
      "$workload" "$max_tokens" "$MAX_NUM_BATCHED_TOKENS" "$run_status" \
      "" "" "" "" "" "$startup_seconds" "$run_notes" >>"$MTP_SUMMARY_CSV"
    return 0
  fi

  local median_elapsed
  local median_tps
  median_elapsed="$(median_from_list "${elapsed_values[@]}")"
  median_tps="$(median_from_list "${tps_values[@]}")"

  local draft_before
  local draft_after
  local accepted_before
  local accepted_after
  local draft_delta
  local accepted_delta
  local acceptance_rate
  draft_before="$(metric_value "$metrics_before" "spec_decode_num_draft_tokens_total")"
  draft_after="$(metric_value "$metrics_after" "spec_decode_num_draft_tokens_total")"
  accepted_before="$(metric_value "$metrics_before" "spec_decode_num_accepted_tokens_total")"
  accepted_after="$(metric_value "$metrics_after" "spec_decode_num_accepted_tokens_total")"
  draft_delta="$(python3 - "$draft_before" "$draft_after" <<'PY'
import sys
print(f"{float(sys.argv[2]) - float(sys.argv[1]):.0f}")
PY
)"
  accepted_delta="$(python3 - "$accepted_before" "$accepted_after" <<'PY'
import sys
print(f"{float(sys.argv[2]) - float(sys.argv[1]):.0f}")
PY
)"
  acceptance_rate="$(format_rate "$accepted_delta" "$draft_delta")"

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$CONFIG_ID" "$LABEL" "$QUANT" "$SPEC_METHOD" "$NUM_SPECULATIVE_TOKENS" \
    "$workload" "$max_tokens" "$MAX_NUM_BATCHED_TOKENS" "ok" "$median_elapsed" \
    "$median_tps" "$draft_delta" "$accepted_delta" "$acceptance_rate" \
    "$startup_seconds" "" >>"$MTP_SUMMARY_CSV"
}

generate_spec_compare() {
  python3 - "$EXISTING_SUMMARY_CSV" "$MTP_SUMMARY_CSV" "$SPEC_COMPARE_CSV" "$SPEC_COMPARE_MD" <<'PY'
import csv
import sys
from collections import defaultdict

existing_summary, mtp_summary, compare_csv, compare_md = sys.argv[1:5]

rows = []
with open(existing_summary, encoding="utf-8", newline="") as f:
    for row in csv.DictReader(f):
        if row["config_id"] not in {"Base-FP8", "DFlash-FP8-n15"}:
            continue
        rows.append({
            "config_id": row["config_id"],
            "label": row["label"],
            "quantization": row["quantization"],
            "spec_method": "none" if row["config_id"] == "Base-FP8" else "dflash",
            "num_speculative_tokens": row["num_speculative_tokens"],
            "workload": row["workload"],
            "max_tokens": row["max_tokens"],
            "max_num_batched_tokens": row["max_num_batched_tokens"],
            "status": row["status"],
            "median_elapsed_ms": row["median_elapsed_ms"],
            "median_tok_per_s": row["median_tok_per_s"],
            "draft_tokens": row["draft_tokens"],
            "accepted_tokens": row["accepted_tokens"],
            "acceptance_rate": row["acceptance_rate"],
            "startup_seconds": row["startup_seconds"],
            "notes": row["notes"],
        })

with open(mtp_summary, encoding="utf-8", newline="") as f:
    rows.extend(csv.DictReader(f))

baseline = {
    row["workload"]: float(row["median_tok_per_s"])
    for row in rows
    if row["config_id"] == "Base-FP8" and row["status"] == "ok" and row["median_tok_per_s"]
}
dflash = {
    row["workload"]: float(row["median_tok_per_s"])
    for row in rows
    if row["config_id"] == "DFlash-FP8-n15" and row["status"] == "ok" and row["median_tok_per_s"]
}

fieldnames = [
    "config_id", "label", "quantization", "spec_method",
    "num_speculative_tokens", "workload", "max_tokens",
    "max_num_batched_tokens", "status", "median_elapsed_ms",
    "median_tok_per_s", "speedup_vs_baseline", "speedup_vs_dflash",
    "draft_tokens", "accepted_tokens", "acceptance_rate",
    "startup_seconds", "notes",
]

for row in rows:
    tok = row.get("median_tok_per_s")
    if row["status"] == "ok" and tok:
        tok_f = float(tok)
        base = baseline.get(row["workload"])
        df = dflash.get(row["workload"])
        row["speedup_vs_baseline"] = f"{tok_f / base:.4f}" if base else ""
        row["speedup_vs_dflash"] = f"{tok_f / df:.4f}" if df else ""
    else:
        row["speedup_vs_baseline"] = ""
        row["speedup_vs_dflash"] = ""

order = {"Base-FP8": 0, "DFlash-FP8-n15": 1, "MTP-FP8-n3": 2}
rows.sort(key=lambda r: (r["workload"], order.get(r["config_id"], 99)))

with open(compare_csv, "w", encoding="utf-8", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    for row in rows:
        writer.writerow({name: row.get(name, "") for name in fieldnames})

grouped = defaultdict(list)
for row in rows:
    grouped[row["workload"]].append(row)

with open(compare_md, "w", encoding="utf-8") as out:
    out.write("# Qwen3.5-4B Speculative Decoding Compare\n\n")
    out.write("Common settings: FP8 target, `--enforce-eager`, max-num-batched-tokens 4096, max model len 2048, concurrency 1, warmup 1 + measured 5.\n\n")
    for workload in ("medium", "long"):
        out.write(f"## {workload}\n\n")
        out.write("| Config | Method | n | tok/s median | Speedup vs baseline | Speedup vs D-Flash | Acceptance | Status |\n")
        out.write("| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |\n")
        for row in grouped.get(workload, []):
            tok = f"{float(row['median_tok_per_s']):.2f}" if row["status"] == "ok" and row["median_tok_per_s"] else ""
            base_sp = f"{float(row['speedup_vs_baseline']):.2f}" if row.get("speedup_vs_baseline") else ""
            df_sp = f"{float(row['speedup_vs_dflash']):.2f}" if row.get("speedup_vs_dflash") else ""
            acceptance = row.get("acceptance_rate") or "-"
            out.write(
                f"| {row['config_id']} {row['label']} | {row['spec_method']} | "
                f"{row['num_speculative_tokens']} | {tok} | {base_sp} | "
                f"{df_sp} | {acceptance} | {row['status']} |\n"
            )
        out.write("\n")
PY
}

if [ "$DRY_RUN" = "--dry-run" ]; then
  echo "out_dir=$OUT_DIR"
  echo "config=$CONFIG_ID script=$SCRIPT_NAME method=$SPEC_METHOD n=$NUM_SPECULATIVE_TOKENS model=$MODEL"
  echo "max_num_batched_tokens=$MAX_NUM_BATCHED_TOKENS"
  echo "max_model_len=$MAX_MODEL_LEN"
  echo "gpu_memory_utilization=$GPU_MEMORY_UTILIZATION"
  exit 0
fi

acquire_lock
init_output_files

startup_log="$LOG_DIR/${CONFIG_ID}_startup.log"
startup_seconds=""

stop_server
echo "==> starting $CONFIG_ID ($LABEL)"
if ! MAX_NUM_BATCHED_TOKENS="$MAX_NUM_BATCHED_TOKENS" \
  MAX_MODEL_LEN="$MAX_MODEL_LEN" \
  GPU_MEMORY_UTILIZATION="$GPU_MEMORY_UTILIZATION" \
  NUM_SPECULATIVE_TOKENS="$NUM_SPECULATIVE_TOKENS" \
  bash "$SCRIPT_DIR/$SCRIPT_NAME" >/dev/null; then
  for workload in "${WORKLOADS[@]}"; do
    IFS='|' read -r workload_name max_tokens prompt_file <<<"$workload"
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$CONFIG_ID" "$LABEL" "$QUANT" "$SPEC_METHOD" "$NUM_SPECULATIVE_TOKENS" \
      "$workload_name" "$max_tokens" "$MAX_NUM_BATCHED_TOKENS" "launch_failed" \
      "" "" "" "" "" "" "launch_failed" >>"$MTP_SUMMARY_CSV"
  done
  stop_server
  generate_spec_compare
  exit 0
fi

if ! startup_seconds="$(wait_for_startup "$startup_log")"; then
  for workload in "${WORKLOADS[@]}"; do
    IFS='|' read -r workload_name max_tokens prompt_file <<<"$workload"
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$CONFIG_ID" "$LABEL" "$QUANT" "$SPEC_METHOD" "$NUM_SPECULATIVE_TOKENS" \
      "$workload_name" "$max_tokens" "$MAX_NUM_BATCHED_TOKENS" "startup_failed" \
      "" "" "" "" "" "$startup_seconds" "startup_failed" >>"$MTP_SUMMARY_CSV"
  done
  stop_server
  generate_spec_compare
  exit 0
fi

for workload in "${WORKLOADS[@]}"; do
  IFS='|' read -r workload_name max_tokens prompt_file <<<"$workload"
  run_workload "$workload_name" "$max_tokens" "$prompt_file" "$startup_seconds"
done

stop_server
generate_spec_compare
echo "benchmark complete: $OUT_DIR"
