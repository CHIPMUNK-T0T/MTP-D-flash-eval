#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_ROOT="${RESULTS_ROOT:-$ROOT_DIR/results}"
OUT_DIR="${OUT_DIR:-$RESULTS_ROOT/mtp}"
LOG_DIR="${LOG_DIR:-$RESULTS_ROOT/logs/mtp}"
METRICS_DIR="${METRICS_DIR:-$RESULTS_ROOT/metrics/mtp}"
DRY_RUN="${1:-}"

REQUESTS_CSV="$OUT_DIR/requests.csv"
SUMMARY_CSV="$OUT_DIR/summary.csv"
SUMMARY_MD="$OUT_DIR/summary.md"
REVIEW_MD="$OUT_DIR/review.md"

CONFIGS=(
  "Base-FP16|FP16 baseline|fp16|no|0|qwen35-2b-fp16.sh|Qwen/Qwen3.5-2B|4096"
  "MTP-FP16-n1|FP16 MTP n=1|fp16|yes|1|qwen35-2b-fp16-mtp-n1.sh|Qwen/Qwen3.5-2B|4096"
  "MTP-FP16-n3|FP16 MTP n=3|fp16|yes|3|qwen35-2b-fp16-mtp-n3.sh|Qwen/Qwen3.5-2B|4096"
  "MTP-FP16-n5|FP16 MTP n=5|fp16|yes|5|qwen35-2b-fp16-mtp-n5.sh|Qwen/Qwen3.5-2B|4096"
  "Base-AWQ4|AWQ4 baseline|awq4|no|0|qwen35-2b-awq.sh|QuantTrio/Qwen3.5-2B-AWQ|4096"
  "MTP-AWQ4-n1|AWQ4 MTP n=1|awq4|yes|1|qwen35-2b-awq-mtp-n1.sh|QuantTrio/Qwen3.5-2B-AWQ|4096"
  "MTP-AWQ4-n3|AWQ4 MTP n=3|awq4|yes|3|qwen35-2b-awq-mtp-n3.sh|QuantTrio/Qwen3.5-2B-AWQ|4096"
  "MTP-AWQ4-n5|AWQ4 MTP n=5|awq4|yes|5|qwen35-2b-awq-mtp-n5.sh|QuantTrio/Qwen3.5-2B-AWQ|4096"
  "Base-FP8|FP8 baseline|fp8|no|0|qwen35-2b-fp8.sh|lovedheart/Qwen3.5-2B-FP8|4096"
  "MTP-FP8-n1|FP8 MTP n=1|fp8|yes|1|qwen35-2b-fp8-mtp-n1.sh|lovedheart/Qwen3.5-2B-FP8|4096 3072 2048"
  "MTP-FP8-n3|FP8 MTP n=3|fp8|yes|3|qwen35-2b-fp8-mtp-n3.sh|lovedheart/Qwen3.5-2B-FP8|4096 3072 2048"
  "MTP-FP8-n5|FP8 MTP n=5|fp8|yes|5|qwen35-2b-fp8-mtp-n5.sh|lovedheart/Qwen3.5-2B-FP8|4096 3072 2048"
)

PROMPT_DIR="${PROMPT_DIR:-$SCRIPT_DIR/../prompts}"
WORKLOADS=(
  "medium|256|$PROMPT_DIR/medium.txt"
  "long|512|$PROMPT_DIR/long.txt"
)

init_output_dir() {
  case "$OUT_DIR" in
    ""|"/"|"$ROOT_DIR"|"$SCRIPT_DIR")
      echo "unsafe OUT_DIR: $OUT_DIR" >&2
      exit 1
      ;;
  esac

  mkdir -p "$OUT_DIR"
  rm -rf "$OUT_DIR/responses" "$LOG_DIR" "$METRICS_DIR"
  rm -f "$REQUESTS_CSV" "$SUMMARY_CSV" "$SUMMARY_MD" "$REVIEW_MD"
  mkdir -p "$OUT_DIR/responses" "$LOG_DIR" "$METRICS_DIR"

  cat > "$REQUESTS_CSV" <<'EOF'
config_id,label,quantization,mtp,num_speculative_tokens,workload,max_tokens,run_index,elapsed_ms,completion_tokens,tok_per_s,status
EOF

  cat > "$SUMMARY_CSV" <<'EOF'
config_id,label,quantization,mtp,num_speculative_tokens,workload,max_tokens,batched_tokens,status,median_elapsed_ms,median_tok_per_s,draft_tokens,accepted_tokens,acceptance_rate,startup_seconds,notes
EOF
}

stop_server() {
  docker stop vllm-server >/dev/null 2>&1 || true
  docker rm vllm-server >/dev/null 2>&1 || true
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
payload = {
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
}
print(json.dumps(payload, ensure_ascii=False))
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
            parts = line.strip().split()
            if not parts:
                continue
            try:
                value += float(parts[-1])
            except ValueError:
                pass
except FileNotFoundError:
    pass
print(value)
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
if draft <= 0:
    print("")
else:
    print(f"{accepted / draft:.4f}")
PY
}

generate_summary_markdown() {
  python3 - "$SUMMARY_CSV" "$SUMMARY_MD" <<'PY'
import csv
import sys
from collections import defaultdict

summary_csv, summary_md = sys.argv[1], sys.argv[2]
with open(summary_csv, encoding="utf-8") as f:
    rows = list(csv.DictReader(f))

baseline = {}
for row in rows:
    if row["status"] == "ok" and row["config_id"] == "Base-FP16":
        baseline[row["workload"]] = float(row["median_tok_per_s"])

grouped = defaultdict(list)
for row in rows:
    grouped[row["workload"]].append(row)

with open(summary_md, "w", encoding="utf-8") as out:
    out.write("# MTP Benchmark Summary\n\n")
    for workload in ("medium", "long"):
        out.write(f"## {workload}\n\n")
        out.write("| Config | Quant | MTP | n | Batched | tok/s median | Speedup vs Base-FP16 | Acceptance | Notes |\n")
        out.write("| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |\n")
        for row in grouped.get(workload, []):
            tok = ""
            speedup = ""
            acceptance = row["acceptance_rate"] or "-"
            if row["status"] == "ok" and row["median_tok_per_s"]:
                tok = f"{float(row['median_tok_per_s']):.2f}"
                base = baseline.get(workload)
                if base:
                    speedup = f"{float(row['median_tok_per_s']) / base:.2f}"
            out.write(
                f"| {row['config_id']} | {row['quantization']} | {row['mtp']} | "
                f"{row['num_speculative_tokens']} | {row['batched_tokens']} | {tok} | "
                f"{speedup} | {acceptance} | {row['notes']} |\n"
            )
        out.write("\n")
PY
}

generate_result_review() {
  python3 - "$SUMMARY_CSV" "$OUT_DIR/responses" "$REVIEW_MD" <<'PY'
import csv
import sys
from collections import Counter
from pathlib import Path

summary_csv = Path(sys.argv[1])
responses_dir = Path(sys.argv[2])
review_md = Path(sys.argv[3])

with summary_csv.open(encoding="utf-8", newline="") as f:
    rows = list(csv.DictReader(f))

failed = [r for r in rows if r["status"] != "ok"]
quality_issues = []

for response_dir in sorted(responses_dir.iterdir()):
    if not response_dir.is_dir():
        continue
    bad_runs = []
    for path in sorted(response_dir.glob("run*.txt")):
        text = path.read_text(encoding="utf-8", errors="replace")
        chunks = [text[i:i + 8] for i in range(max(0, len(text) - 7))]
        diversity = len(set(chunks)) / len(chunks) if chunks else 1.0
        top_chunk, top_count = ("", 0)
        if chunks:
            top_chunk, top_count = Counter(chunks).most_common(1)[0]
        repeated_prompt_clause = (
            "導入目的の整理は、導入目的の整理は" in text
        )
        if repeated_prompt_clause or diversity < 0.08:
            bad_runs.append((path.name, top_chunk, top_count, diversity))
    if bad_runs:
        quality_issues.append((response_dir.name, bad_runs))

with review_md.open("w", encoding="utf-8") as out:
    out.write("# Result Review\n\n")
    out.write("## Runtime/API status\n\n")
    if failed:
        for row in failed:
            out.write(
                f"- {row['config_id']}_{row['workload']}: "
                f"status={row['status']}, notes={row['notes']}\n"
            )
    else:
        out.write("- No runtime/API failures were recorded.\n")

    out.write("\n## Quality scan\n\n")
    if quality_issues:
        out.write(
            "Potential repetition loops were detected in these response sets:\n\n"
        )
        for name, bad_runs in quality_issues:
            out.write(f"- {name}: {len(bad_runs)} run(s)\n")
            run_name, top_chunk, top_count, diversity = bad_runs[0]
            out.write(
                f"  - sample={run_name}, top8={top_chunk!r}, "
                f"count={top_count}, diversity={diversity:.3f}\n"
            )
    else:
        out.write("- No obvious repetition loops were detected by the simple scan.\n")
PY
}

wait_for_startup() {
  local startup_log="$1"
  local timeout=600
  local elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    docker logs vllm-server >"$startup_log" 2>&1 || true
    if grep -q "startup complete" "$startup_log"; then
      echo "$elapsed"
      return 0
    fi
    if grep -qE "RuntimeError|OutOfMemoryError|Engine core initialization failed|OOM" "$startup_log"; then
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
  local config_id="$1"
  local label="$2"
  local quant="$3"
  local mtp="$4"
  local spec_n="$5"
  local model="$6"
  local workload="$7"
  local max_tokens="$8"
  local prompt_file="$9"
  local batched_tokens="${10}"
  local startup_seconds="${11}"

  local payload
  payload="$(build_payload "$model" "$prompt_file" "$max_tokens")"

  local response_dir="$OUT_DIR/responses/${config_id}_${workload}"
  mkdir -p "$response_dir"

  local warmup_json="$response_dir/warmup.json"
  if ! curl -s --max-time 300 http://localhost:8000/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "$payload" >"$warmup_json"; then
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$config_id" "$label" "$quant" "$mtp" "$spec_n" "$workload" "$max_tokens" \
      "$batched_tokens" "warmup_failed" "" "" "" "" "" "$startup_seconds" "warmup_curl_failed" >>"$SUMMARY_CSV"
    return 0
  fi

  local metrics_before="$METRICS_DIR/${config_id}_${workload}_before.prom"
  local metrics_after="$METRICS_DIR/${config_id}_${workload}_after.prom"
  if [ "$mtp" = "yes" ]; then
    curl -s http://localhost:8000/metrics >"$metrics_before"
  fi

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
    if ! curl -s --max-time 300 http://localhost:8000/v1/chat/completions \
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
      "$config_id" "$label" "$quant" "$mtp" "$spec_n" "$workload" "$max_tokens" \
      "$run_index" "$elapsed_ms" "$completion_tokens" "$tok_per_s" "ok" >>"$REQUESTS_CSV"
  done

  if [ "$mtp" = "yes" ]; then
    curl -s http://localhost:8000/metrics >"$metrics_after"
  fi

  if [ "$run_status" != "ok" ]; then
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$config_id" "$label" "$quant" "$mtp" "$spec_n" "$workload" "$max_tokens" \
      "$batched_tokens" "$run_status" "" "" "" "" "" "$startup_seconds" "$run_notes" >>"$SUMMARY_CSV"
    return 0
  fi

  local median_elapsed
  local median_tps
  median_elapsed="$(median_from_list "${elapsed_values[@]}")"
  median_tps="$(median_from_list "${tps_values[@]}")"

  local draft_delta=""
  local accepted_delta=""
  local acceptance_rate=""

  if [ "$mtp" = "yes" ]; then
    local draft_before
    local draft_after
    local accepted_before
    local accepted_after
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
  fi

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$config_id" "$label" "$quant" "$mtp" "$spec_n" "$workload" "$max_tokens" \
    "$batched_tokens" "ok" "$median_elapsed" "$median_tps" "$draft_delta" \
    "$accepted_delta" "$acceptance_rate" "$startup_seconds" "" >>"$SUMMARY_CSV"
}

if [ "$DRY_RUN" = "--dry-run" ]; then
  echo "out_dir=$OUT_DIR"
  for config in "${CONFIGS[@]}"; do
    IFS='|' read -r config_id label quant mtp spec_n script_name model batched_options <<<"$config"
    echo "config=$config_id script=$script_name mtp=$mtp n=$spec_n batched_options=[$batched_options]"
    for workload in "${WORKLOADS[@]}"; do
      IFS='|' read -r workload_name max_tokens prompt_file <<<"$workload"
      echo "  workload=$workload_name max_tokens=$max_tokens prompt=$prompt_file"
    done
  done
  exit 0
fi

init_output_dir

for config in "${CONFIGS[@]}"; do
  IFS='|' read -r config_id label quant mtp spec_n script_name model batched_options <<<"$config"
  success=0
  startup_seconds=""
  chosen_batched=""
  notes=""

  for batched in $batched_options; do
    stop_server
    startup_log="$LOG_DIR/${config_id}_startup_${batched}.log"
    echo "==> starting $config_id ($label) batched=$batched"
    if [ "$mtp" = "yes" ]; then
      if ! MAX_NUM_BATCHED_TOKENS="$batched" bash "$SCRIPT_DIR/$script_name" >/dev/null; then
        notes="launch_failed_batched_${batched}"
        stop_server
        continue
      fi
    else
      if ! bash "$SCRIPT_DIR/$script_name" >/dev/null; then
        notes="launch_failed_batched_${batched}"
        stop_server
        continue
      fi
    fi

    if startup_seconds="$(wait_for_startup "$startup_log")"; then
      success=1
      chosen_batched="$batched"
      break
    fi
    notes="startup_failed_batched_${batched}"
    stop_server
  done

  if [ "$success" -ne 1 ]; then
    for workload in "${WORKLOADS[@]}"; do
      IFS='|' read -r workload_name max_tokens prompt_file <<<"$workload"
      printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$config_id" "$label" "$quant" "$mtp" "$spec_n" "$workload_name" "$max_tokens" \
        "${chosen_batched:-}" "startup_failed" "" "" "" "" "" "$startup_seconds" "$notes" >>"$SUMMARY_CSV"
    done
    continue
  fi

  for workload in "${WORKLOADS[@]}"; do
    IFS='|' read -r workload_name max_tokens prompt_file <<<"$workload"
    run_workload "$config_id" "$label" "$quant" "$mtp" "$spec_n" "$model" \
      "$workload_name" "$max_tokens" "$prompt_file" "$chosen_batched" "$startup_seconds"
  done

  stop_server
done

generate_summary_markdown
generate_result_review
echo "benchmark complete: $OUT_DIR"
