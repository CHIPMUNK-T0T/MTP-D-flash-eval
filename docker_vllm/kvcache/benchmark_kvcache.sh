#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_ROOT="${RESULTS_ROOT:-$ROOT_DIR/results_kvcache}"
OUT_DIR="${OUT_DIR:-$RESULTS_ROOT}"
LOG_DIR="${LOG_DIR:-$RESULTS_ROOT/logs}"
DRY_RUN="${1:-}"

REQUESTS_CSV="$OUT_DIR/requests.csv"
SUMMARY_CSV="$OUT_DIR/summary.csv"
SUMMARY_MD="$OUT_DIR/summary.md"
REVIEW_MD="$OUT_DIR/review.md"
LOCK_DIR="$OUT_DIR/.benchmark.lock"

MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-4096}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.937}"

MODEL="RedHatAI/Qwen3.5-4B-FP8-dynamic"

# config_id|label|kv_cache_dtype|max_model_len|script_name
# base_fa:    auto KV + flash_attn  (継続性確認用)
# base_fi_*:  auto KV + flashinfer  (fp8kv_* と直接比較)
# fp8kv_*:    fp8 KV + flashinfer
# 96k ペア:   OOM 境界確認。auto は kv pool (~89,600) < max_model_len (98,304) で起動失敗予定
CONFIGS=(
  "base_fa|base_fa|auto|2048|qwen35-4b-kv-auto-flash_attn.sh"
  "base_fi|base_fi|auto|2048|qwen35-4b-kv-auto-flashinfer.sh"
  "base_fi_8k|base_fi_8k|auto|8192|qwen35-4b-kv-auto-flashinfer.sh"
  "base_fi_32k|base_fi_32k|auto|32768|qwen35-4b-kv-auto-flashinfer.sh"
  "base_fi_64k|base_fi_64k|auto|65536|qwen35-4b-kv-auto-flashinfer.sh"
  "base_fi_96k|base_fi_96k|auto|98304|qwen35-4b-kv-auto-flashinfer.sh"
  "fp8kv_2k|fp8kv_2k|fp8|2048|qwen35-4b-kv-fp8-flashinfer.sh"
  "fp8kv_8k|fp8kv_8k|fp8|8192|qwen35-4b-kv-fp8-flashinfer.sh"
  "fp8kv_32k|fp8kv_32k|fp8|32768|qwen35-4b-kv-fp8-flashinfer.sh"
  "fp8kv_64k|fp8kv_64k|fp8|65536|qwen35-4b-kv-fp8-flashinfer.sh"
  "fp8kv_96k|fp8kv_96k|fp8|98304|qwen35-4b-kv-fp8-flashinfer.sh"
)

PROMPT_DIR="${PROMPT_DIR:-$SCRIPT_DIR/../prompts}"
WORKLOADS=(
  "medium|256|$PROMPT_DIR/medium.txt"
  "long|512|$PROMPT_DIR/long.txt"
  "ctx_long|256|$PROMPT_DIR/ctx_long.txt"
  "ctx_8k|256|$PROMPT_DIR/ctx_8k.txt"
  "ctx_32k|256|$PROMPT_DIR/ctx_32k.txt"
)

init_output_dir() {
  case "$OUT_DIR" in
    ""|"/"|"$ROOT_DIR"|"$SCRIPT_DIR")
      echo "unsafe OUT_DIR: $OUT_DIR" >&2
      exit 1
      ;;
  esac

  mkdir -p "$OUT_DIR"
  rm -rf "$OUT_DIR/responses" "$LOG_DIR"
  rm -f "$REQUESTS_CSV" "$SUMMARY_CSV" "$SUMMARY_MD" "$REVIEW_MD"
  mkdir -p "$OUT_DIR/responses" "$LOG_DIR"

  cat > "$REQUESTS_CSV" <<'EOF'
config_id,label,kv_cache_dtype,max_model_len,workload,max_tokens,run_index,elapsed_ms,completion_tokens,tok_per_s,status
EOF

  cat > "$SUMMARY_CSV" <<'EOF'
config_id,label,kv_cache_dtype,max_model_len,workload,max_tokens,max_num_batched_tokens,status,median_elapsed_ms,median_tok_per_s,ttft_ms,kv_cache_tokens,startup_seconds,notes
EOF
}

stop_server() {
  docker stop vllm-server >/dev/null 2>&1 || true
  docker rm vllm-server >/dev/null 2>&1 || true
}

acquire_lock() {
  mkdir -p "$OUT_DIR"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "another benchmark_kvcache_4b.sh run appears to be active: $LOCK_DIR" >&2
    exit 1
  fi
  trap 'stop_server; rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
}

build_payload() {
  local model="$1"
  local prompt_file="$2"
  local max_tokens="$3"
  python3 - "$model" "$prompt_file" "$max_tokens" <<'PY'
import json, sys
model, prompt_file, max_tokens = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(prompt_file, encoding="utf-8") as f:
    prompt = f.read()
print(json.dumps({
    "model": model,
    "messages": [{"role": "user", "content": prompt}],
    "max_tokens": max_tokens,
    "temperature": 0,
    "chat_template_kwargs": {"enable_thinking": False},
}, ensure_ascii=False))
PY
}

measure_ttft() {
  local model="$1"
  local prompt_file="$2"
  local max_tokens="$3"
  python3 - "$model" "$prompt_file" "$max_tokens" <<'PY'
import json, sys, time, urllib.request
model, prompt_file, max_tokens = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(prompt_file, encoding="utf-8") as f:
    prompt = f.read()
payload = json.dumps({
    "model": model,
    "messages": [{"role": "user", "content": prompt}],
    "max_tokens": max_tokens,
    "temperature": 0,
    "stream": True,
    "chat_template_kwargs": {"enable_thinking": False},
}, ensure_ascii=False).encode("utf-8")
req = urllib.request.Request(
    "http://localhost:8000/v1/chat/completions",
    data=payload,
    headers={"Content-Type": "application/json"},
)
start = time.time()
ttft_ms = -1
try:
    with urllib.request.urlopen(req, timeout=120) as resp:
        for raw_line in resp:
            line = raw_line.decode("utf-8").strip()
            if line.startswith("data: ") and line != "data: [DONE]":
                ttft_ms = int((time.time() - start) * 1000)
                break
except Exception:
    pass
print(ttft_ms)
PY
}

extract_response_field() {
  local response_file="$1"
  local field="$2"
  python3 - "$response_file" "$field" <<'PY'
import json, sys
path, field = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
if "error" in data:
    err = data["error"]
    if isinstance(err, dict) and (
        err.get("code") == "context_length_exceeded"
        or (err.get("code") == 400 and "context length" in err.get("message", "").lower())
        or (err.get("type") == "BadRequestError" and "input tokens" in err.get("message", ""))
    ):
        print("CTX_TOO_LONG")
        sys.exit(0)
    raise SystemExit(str(err))
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
print(f"{values[mid]:.4f}" if len(values) % 2 else f"{(values[mid-1]+values[mid])/2:.4f}")
PY
}

get_kv_cache_tokens() {
  local startup_log="$1"
  grep -oP 'GPU KV cache size: \K[\d,]+' "$startup_log" 2>/dev/null | tail -1 | tr -d ','
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
    # OOM: CUDA out of memory
    if grep -qE "OutOfMemoryError|CUDA out of memory|No available memory for KV" "$startup_log"; then
      echo "$elapsed"
      return 2
    fi
    # ValueError: max_model_len exceeds model's native context limit, or other config error
    if grep -qE "ValueError|Engine core initialization failed|RuntimeError" "$startup_log"; then
      echo "$elapsed"
      return 3
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
  local kv_dtype="$3"
  local max_model_len="$4"
  local workload="$5"
  local max_tokens="$6"
  local prompt_file="$7"
  local startup_seconds="$8"
  local kv_cache_tokens="$9"

  local payload
  payload="$(build_payload "$MODEL" "$prompt_file" "$max_tokens")"

  local response_dir="$OUT_DIR/responses/${config_id}_${workload}"
  mkdir -p "$response_dir"

  # 1回目は Triton JIT コンパイルで遅いため捨てる (結果は保存しない)
  curl -s --max-time 180 http://localhost:8000/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null || true
  echo "    warmup done"

  # 2回目以降: TTFT 計測 (ストリーミング)
  local ttft_ms=""
  ttft_ms="$(measure_ttft "$MODEL" "$prompt_file" "$max_tokens" 2>/dev/null)" || ttft_ms="-1"
  echo "    ttft=${ttft_ms}ms"

  local elapsed_values=()
  local tps_values=()
  local run_status="ok"
  local run_notes=""

  for run_index in 1 2 3 4 5; do
    local response_json="$response_dir/run${run_index}.json"
    local response_txt="$response_dir/run${run_index}.txt"
    local start_ms end_ms elapsed_ms
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
    if [ "$completion_tokens" = "CTX_TOO_LONG" ]; then
      run_status="ctx_too_long"
      run_notes=""
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
print(f"{float(sys.argv[1]) / (float(sys.argv[2]) / 1000):.4f}")
PY
)"
    elapsed_values+=("$elapsed_ms")
    tps_values+=("$tok_per_s")

    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$config_id" "$label" "$kv_dtype" "$max_model_len" "$workload" "$max_tokens" \
      "$run_index" "$elapsed_ms" "$completion_tokens" "$tok_per_s" "ok" >>"$REQUESTS_CSV"
  done

  if [ "$run_status" != "ok" ]; then
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$config_id" "$label" "$kv_dtype" "$max_model_len" "$workload" "$max_tokens" \
      "$MAX_NUM_BATCHED_TOKENS" "$run_status" "" "" "$ttft_ms" "$kv_cache_tokens" \
      "$startup_seconds" "$run_notes" >>"$SUMMARY_CSV"
    return 0
  fi

  local median_elapsed median_tps
  median_elapsed="$(median_from_list "${elapsed_values[@]}")"
  median_tps="$(median_from_list "${tps_values[@]}")"

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$config_id" "$label" "$kv_dtype" "$max_model_len" "$workload" "$max_tokens" \
    "$MAX_NUM_BATCHED_TOKENS" "ok" "$median_elapsed" "$median_tps" \
    "$ttft_ms" "$kv_cache_tokens" "$startup_seconds" "" >>"$SUMMARY_CSV"
}

generate_summary_markdown() {
  python3 - "$SUMMARY_CSV" "$SUMMARY_MD" <<'PY'
import csv, sys
from collections import defaultdict

summary_csv, summary_md = sys.argv[1], sys.argv[2]
with open(summary_csv, encoding="utf-8") as f:
    rows = list(csv.DictReader(f))

baseline = {}
for row in rows:
    if row["status"] == "ok" and row["config_id"] == "base_fa":
        baseline[row["workload"]] = float(row["median_tok_per_s"])

grouped = defaultdict(list)
for row in rows:
    grouped[row["workload"]].append(row)

with open(summary_md, "w", encoding="utf-8") as out:
    out.write("# Qwen3.5-4B KV Cache Benchmark Summary\n\n")
    out.write("Model: `RedHatAI/Qwen3.5-4B-FP8-dynamic`, `--enforce-eager`, "
              "max-num-batched-tokens 4096, concurrency 1, "
              "throwaway warmup 1 + TTFT(streaming) 1 + measured 5.\n\n")
    out.write("Status legend: `ok`=success, `ctx_too_long`=prompt exceeded max_model_len, "
              "`oom`=CUDA out of memory at startup, `model_limit`=vLLM ValueError at startup.\n\n")
    for workload in ("medium", "long", "ctx_long", "ctx_8k", "ctx_32k"):
        if workload not in grouped:
            continue
        out.write(f"## {workload}\n\n")
        out.write("| Config | kv_cache_dtype | max_model_len | tok/s | vs KV0 | TTFT ms | KV tokens | Status |\n")
        out.write("| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |\n")
        for row in grouped[workload]:
            tok = speedup = ""
            if row["status"] == "ok" and row["median_tok_per_s"]:
                tok = f"{float(row['median_tok_per_s']):.2f}"
                base = baseline.get(workload)
                if base:
                    speedup = f"{float(row['median_tok_per_s']) / base:.3f}x"
            kv_tokens = row.get('kv_cache_tokens', '')
            out.write(
                f"| {row['config_id']} | {row['kv_cache_dtype']} | {row['max_model_len']} | "
                f"{tok} | {speedup} | {row.get('ttft_ms','')} | {kv_tokens} | {row['status']} |\n"
            )
        out.write("\n")
PY
}

generate_result_review() {
  python3 - "$SUMMARY_CSV" "$OUT_DIR/responses" "$REVIEW_MD" <<'PY'
import csv, sys
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
        chunks = [text[i:i+8] for i in range(max(0, len(text)-7))]
        diversity = len(set(chunks)) / len(chunks) if chunks else 1.0
        top_chunk, top_count = ("", 0)
        if chunks:
            top_chunk, top_count = Counter(chunks).most_common(1)[0]
        if diversity < 0.08 or top_count > 80:
            bad_runs.append((path.name, top_chunk, top_count, diversity))
    if bad_runs:
        quality_issues.append((response_dir.name, bad_runs))

with review_md.open("w", encoding="utf-8") as out:
    out.write("# Qwen3.5-4B KV Cache Result Review\n\n")
    out.write("## Runtime/API status\n\n")
    if failed:
        for row in failed:
            out.write(f"- {row['config_id']}_{row['workload']}: status={row['status']}, notes={row.get('notes','')}\n")
    else:
        out.write("- No runtime/API failures.\n")
    out.write("\n## Quality scan\n\n")
    if quality_issues:
        out.write("Potential repetition loops detected:\n\n")
        for name, bad_runs in quality_issues:
            out.write(f"- {name}: {len(bad_runs)} run(s)\n")
            run_name, top_chunk, top_count, diversity = bad_runs[0]
            out.write(f"  - sample={run_name}, top8={top_chunk!r}, count={top_count}, diversity={diversity:.3f}\n")
    else:
        out.write("- No obvious repetition loops detected.\n")
PY
}

if [ "$DRY_RUN" = "--dry-run" ]; then
  echo "out_dir=$OUT_DIR"
  echo "max_num_batched_tokens=$MAX_NUM_BATCHED_TOKENS"
  echo "gpu_memory_utilization=$GPU_MEMORY_UTILIZATION"
  for config in "${CONFIGS[@]}"; do
    IFS='|' read -r config_id label kv_dtype max_model_len script_name <<<"$config"
    echo "config=$config_id kv_dtype=$kv_dtype max_model_len=$max_model_len script=$script_name"
  done
  exit 0
fi

acquire_lock
init_output_dir

for config in "${CONFIGS[@]}"; do
  IFS='|' read -r config_id label kv_dtype max_model_len script_name <<<"$config"
  startup_log="$LOG_DIR/${config_id}_startup.log"

  stop_server
  echo "==> starting $config_id ($label)"
  if ! MAX_NUM_BATCHED_TOKENS="$MAX_NUM_BATCHED_TOKENS" \
    MAX_MODEL_LEN="$max_model_len" \
    GPU_MEMORY_UTILIZATION="$GPU_MEMORY_UTILIZATION" \
    bash "$SCRIPT_DIR/$script_name" >/dev/null; then
    for workload_entry in "${WORKLOADS[@]}"; do
      IFS='|' read -r workload_name max_tokens prompt_file <<<"$workload_entry"
      printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$config_id" "$label" "$kv_dtype" "$max_model_len" "$workload_name" "$max_tokens" \
        "$MAX_NUM_BATCHED_TOKENS" "launch_failed" "" "" "" "" "" "launch_failed" >>"$SUMMARY_CSV"
    done
    stop_server
    continue
  fi

  startup_seconds=""
  startup_rc=0
  startup_seconds="$(wait_for_startup "$startup_log")" || startup_rc=$?
  if [ "$startup_rc" -ne 0 ]; then
    kv_cache_tokens="$(get_kv_cache_tokens "$startup_log")" || kv_cache_tokens=""
    case "$startup_rc" in
      2) startup_status="oom" ;;
      3) startup_status="model_limit" ;;
      *) startup_status="startup_failed" ;;
    esac
    echo "  ${startup_status} after ${startup_seconds}s"
    for workload_entry in "${WORKLOADS[@]}"; do
      IFS='|' read -r workload_name max_tokens prompt_file <<<"$workload_entry"
      printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$config_id" "$label" "$kv_dtype" "$max_model_len" "$workload_name" "$max_tokens" \
        "$MAX_NUM_BATCHED_TOKENS" "$startup_status" "" "" "" "$kv_cache_tokens" "$startup_seconds" "$startup_status" >>"$SUMMARY_CSV"
    done
    stop_server
    continue
  fi

  kv_cache_tokens="$(get_kv_cache_tokens "$startup_log")"
  echo "  ready in ${startup_seconds}s, kv_cache_tokens=${kv_cache_tokens}"

  for workload_entry in "${WORKLOADS[@]}"; do
    IFS='|' read -r workload_name max_tokens prompt_file <<<"$workload_entry"
    echo "  workload=$workload_name max_tokens=$max_tokens"
    run_workload "$config_id" "$label" "$kv_dtype" "$max_model_len" \
      "$workload_name" "$max_tokens" "$prompt_file" "$startup_seconds" "$kv_cache_tokens"
  done

  stop_server
done

generate_summary_markdown
generate_result_review
echo "benchmark complete: $OUT_DIR"
