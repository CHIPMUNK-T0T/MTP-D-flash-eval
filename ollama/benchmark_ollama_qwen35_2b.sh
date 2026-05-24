#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_ROOT="${RESULTS_ROOT:-$ROOT_DIR/results}"
OUT_DIR="${OUT_DIR:-$RESULTS_ROOT/ollama}"
MODEL_NAME="${MODEL_NAME:-qwen35-2b-bench}"
BASE_MODEL="${BASE_MODEL:-qwen3.5:2b}"
MODELFILE="${MODELFILE:-$SCRIPT_DIR/Modelfile.qwen35-2b-bench}"
DRY_RUN="${1:-}"

REQUESTS_CSV="$OUT_DIR/requests.csv"
SUMMARY_CSV="$OUT_DIR/summary.csv"
SUMMARY_MD="$OUT_DIR/summary.md"

PROMPT_DIR="${PROMPT_DIR:-$ROOT_DIR/docker_vllm/prompts}"
WORKLOADS=(
  "medium|256|$PROMPT_DIR/medium.txt"
  "long|512|$PROMPT_DIR/long.txt"
)

check_ollama() {
  curl -sS http://127.0.0.1:11434/api/tags >/dev/null
}

init_output_dir() {
  mkdir -p "$OUT_DIR/responses"
  rm -rf "$OUT_DIR/responses"
  mkdir -p "$OUT_DIR/responses"

  cat > "$REQUESTS_CSV" <<'EOF'
engine,model,workload,max_tokens,run_index,total_duration_ns,load_duration_ns,prompt_eval_count,prompt_eval_duration_ns,eval_count,eval_duration_ns,total_tok_per_s,eval_tok_per_s,status
EOF

  cat > "$SUMMARY_CSV" <<'EOF'
engine,model,workload,max_tokens,status,median_total_duration_ms,median_eval_tok_per_s,median_total_tok_per_s,median_prompt_tok_per_s,notes
EOF
}

json_payload() {
  local prompt_file="$1"
  local max_tokens="$2"
  python3 - "$MODEL_NAME" "$prompt_file" "$max_tokens" <<'PY'
import json
import sys

model, prompt_file, max_tokens = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(prompt_file, encoding="utf-8") as f:
    prompt = f.read()
payload = {
    "model": model,
    "prompt": prompt,
    "stream": False,
    "think": False,
    "options": {
        "temperature": 0,
        "num_ctx": 2048,
        "num_predict": max_tokens,
    },
}
print(json.dumps(payload, ensure_ascii=False))
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

extract_response_text() {
  local response_json="$1"
  local response_txt="$2"
  if jq -e '.error?' "$response_json" >/dev/null; then
    return 1
  fi
  jq -r '.response // ""' "$response_json" >"$response_txt"
}

run_workload() {
  local workload="$1"
  local max_tokens="$2"
  local prompt_file="$3"
  local payload
  payload="$(json_payload "$prompt_file" "$max_tokens")"

  local response_dir="$OUT_DIR/responses/${MODEL_NAME}_${workload}"
  mkdir -p "$response_dir"

  local warmup_json="$response_dir/warmup.json"
  curl -sS --max-time 600 http://127.0.0.1:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "$payload" >"$warmup_json"
  if ! extract_response_text "$warmup_json" "$response_dir/warmup.txt"; then
    local error_message
    error_message="$(jq -r '.error // "unknown_error"' "$warmup_json")"
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "ollama" "$MODEL_NAME" "$workload" "$max_tokens" "warmup_failed" "" "" "" "" "$error_message" >>"$SUMMARY_CSV"
    return 0
  fi

  local eval_tps_values=()
  local total_tps_values=()
  local prompt_tps_values=()
  local total_ms_values=()
  local run_status="ok"
  local notes=""

  for run_index in 1 2 3 4 5; do
    local response_json="$response_dir/run${run_index}.json"
    local response_txt="$response_dir/run${run_index}.txt"

    if ! curl -sS --max-time 600 http://127.0.0.1:11434/api/generate \
      -H "Content-Type: application/json" \
      -d "$payload" >"$response_json"; then
      run_status="request_failed"
      notes="run${run_index}_curl_failed"
      break
    fi

    if ! extract_response_text "$response_json" "$response_txt"; then
      run_status="parse_failed"
      notes="$(jq -r '.error // "run'${run_index}'_parse_failed"' "$response_json")"
      break
    fi

    local total_duration
    local load_duration
    local prompt_eval_count
    local prompt_eval_duration
    local eval_count
    local eval_duration
    total_duration="$(jq -r '.total_duration // 0' "$response_json")"
    load_duration="$(jq -r '.load_duration // 0' "$response_json")"
    prompt_eval_count="$(jq -r '.prompt_eval_count // 0' "$response_json")"
    prompt_eval_duration="$(jq -r '.prompt_eval_duration // 0' "$response_json")"
    eval_count="$(jq -r '.eval_count // 0' "$response_json")"
    eval_duration="$(jq -r '.eval_duration // 0' "$response_json")"

    local calc
    calc="$(python3 - "$total_duration" "$prompt_eval_count" "$prompt_eval_duration" "$eval_count" "$eval_duration" <<'PY'
import sys

total_duration, prompt_count, prompt_duration, eval_count, eval_duration = map(float, sys.argv[1:])
total_ms = total_duration / 1_000_000
eval_tps = eval_count / (eval_duration / 1_000_000_000) if eval_duration > 0 else 0
prompt_tps = prompt_count / (prompt_duration / 1_000_000_000) if prompt_duration > 0 else 0
total_tps = eval_count / (total_duration / 1_000_000_000) if total_duration > 0 else 0
print(f"{total_ms:.4f},{eval_tps:.4f},{total_tps:.4f},{prompt_tps:.4f}")
PY
)"
    IFS=',' read -r total_ms eval_tps total_tps prompt_tps <<<"$calc"

    eval_tps_values+=("$eval_tps")
    total_tps_values+=("$total_tps")
    prompt_tps_values+=("$prompt_tps")
    total_ms_values+=("$total_ms")

    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "ollama" "$MODEL_NAME" "$workload" "$max_tokens" "$run_index" \
      "$total_duration" "$load_duration" "$prompt_eval_count" "$prompt_eval_duration" \
      "$eval_count" "$eval_duration" "$total_tps" "$eval_tps" "ok" >>"$REQUESTS_CSV"
  done

  if [ "$run_status" != "ok" ]; then
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "ollama" "$MODEL_NAME" "$workload" "$max_tokens" "$run_status" "" "" "" "" "$notes" >>"$SUMMARY_CSV"
    return 0
  fi

  local median_total_ms
  local median_eval_tps
  local median_total_tps
  local median_prompt_tps
  median_total_ms="$(median_from_list "${total_ms_values[@]}")"
  median_eval_tps="$(median_from_list "${eval_tps_values[@]}")"
  median_total_tps="$(median_from_list "${total_tps_values[@]}")"
  median_prompt_tps="$(median_from_list "${prompt_tps_values[@]}")"

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "ollama" "$MODEL_NAME" "$workload" "$max_tokens" "ok" \
    "$median_total_ms" "$median_eval_tps" "$median_total_tps" "$median_prompt_tps" "" >>"$SUMMARY_CSV"
}

generate_markdown() {
  python3 - "$SUMMARY_CSV" "$SUMMARY_MD" <<'PY'
import csv
import sys

summary_csv, summary_md = sys.argv[1], sys.argv[2]
with open(summary_csv, encoding="utf-8", newline="") as f:
    rows = list(csv.DictReader(f))

with open(summary_md, "w", encoding="utf-8") as out:
    out.write("# Ollama qwen3.5:2b Benchmark Summary\n\n")
    out.write("vLLMとはAPIと計測方法が異なるため、この記事では参考値として扱う。\n\n")
    out.write("| Engine | Model | Workload | Output tokens | Eval tok/s median | Total tok/s median | Prompt tok/s median | Total latency ms | Notes |\n")
    out.write("| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |\n")
    for row in rows:
        out.write(
            f"| {row['engine']} | {row['model']} | {row['workload']} | {row['max_tokens']} | "
            f"{float(row['median_eval_tok_per_s']):.2f} | {float(row['median_total_tok_per_s']):.2f} | "
            f"{float(row['median_prompt_tok_per_s']):.2f} | {float(row['median_total_duration_ms']):.0f} | {row['notes']} |\n"
        )
PY
}

if [ "$DRY_RUN" = "--dry-run" ]; then
  echo "model=$MODEL_NAME base=$BASE_MODEL modelfile=$MODELFILE out_dir=$OUT_DIR"
  for workload in "${WORKLOADS[@]}"; do
    IFS='|' read -r workload_name max_tokens prompt_file <<<"$workload"
    echo "workload=$workload_name max_tokens=$max_tokens prompt=$prompt_file"
  done
  exit 0
fi

if ! check_ollama; then
  echo "Ollama server is not running on 127.0.0.1:11434" >&2
  exit 1
fi

init_output_dir
ollama pull "$BASE_MODEL"
ollama create "$MODEL_NAME" -f "$MODELFILE"

for workload in "${WORKLOADS[@]}"; do
  IFS='|' read -r workload_name max_tokens prompt_file <<<"$workload"
  run_workload "$workload_name" "$max_tokens" "$prompt_file"
done

generate_markdown
echo "ollama benchmark complete: $OUT_DIR"
