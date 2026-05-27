#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_ROOT="${RESULTS_ROOT:-$SCRIPT_DIR/results/benchmark}"
LOG_DIR="$RESULTS_ROOT/logs"
RESP_DIR="$RESULTS_ROOT/responses"
SUMMARY_CSV="$RESULTS_ROOT/summary.csv"
SUMMARY_MD="$RESULTS_ROOT/summary.md"
REQUESTS_CSV="$RESULTS_ROOT/requests.csv"
DRY_RUN="${1:-}"

MODEL="${MODEL:-RedHatAI/Qwen3.5-4B-FP8-dynamic}"
RUNS="${RUNS:-5}"
WARMUP_RUNS="${WARMUP_RUNS:-1}"
STARTUP_TIMEOUT="${STARTUP_TIMEOUT:-900}"
REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-420}"
MODE="${MODE:-phase1}"
WORKLOAD_FILTER="${WORKLOAD_FILTER:-}"
VLLM_PORT="${VLLM_PORT:-8010}"
SGLANG_PORT="${SGLANG_PORT:-30100}"
VLLM_CONTAINER="${VLLM_CONTAINER:-vllm-backend-compare}"
SGLANG_CONTAINER="${SGLANG_CONTAINER:-sglang-backend-compare}"

PROMPT_DIR="${PROMPT_DIR:-$ROOT_DIR/docker_vllm/prompts}"
COMPARE_PROMPT_DIR="${COMPARE_PROMPT_DIR:-$SCRIPT_DIR/prompts}"
WORKLOADS=(
  "short_ctx512|256|$COMPARE_PROMPT_DIR/ctx512.txt"
  "mid_ctx2048|512|$COMPARE_PROMPT_DIR/ctx2048.txt"
  "long_ctx8192|512|$COMPARE_PROMPT_DIR/ctx8192.txt"
)

if [ -n "$WORKLOAD_FILTER" ]; then
  filtered_workloads=()
  for workload_def in "${WORKLOADS[@]}"; do
    IFS='|' read -r workload _max_tokens _prompt_file <<<"$workload_def"
    if [ "$workload" = "$WORKLOAD_FILTER" ]; then
      filtered_workloads+=("$workload_def")
    fi
  done
  if [ "${#filtered_workloads[@]}" -eq 0 ]; then
    echo "unsupported WORKLOAD_FILTER=$WORKLOAD_FILTER" >&2
    exit 2
  fi
  WORKLOADS=("${filtered_workloads[@]}")
fi

# id|framework|backend|label|kv_cache_dtype|max_batched|gpu_mem|context_len|mem_fraction|chunked_prefill|disable_cuda_graph|priority
PHASE1_CONFIGS=(
  "vllm_flash_attn|vllm|flash_attn|vLLM flash_attn|auto|4096|0.93|8192||||1"
  "vllm_flashinfer|vllm|flashinfer|vLLM flashinfer|auto|4096|0.93|8192||||1"
  "vllm_triton_attn|vllm|triton_attn|vLLM triton_attn|auto|4096|0.93|8192||||1"
  "sglang_flashinfer|sglang|flashinfer|SGLang flashinfer||||8192|0.85||0|1"
  "sglang_triton|sglang|triton|SGLang triton||||8192|0.85||0|1"
)

TUNING_CONFIGS=(
  "vllm_flashinfer_kvfp8|vllm|flashinfer|vLLM flashinfer kv-fp8|fp8|4096|0.93|8192||||2"
  "vllm_flashinfer_bt2048|vllm|flashinfer|vLLM flashinfer batched-2048|auto|2048|0.93|8192||||2"
  "vllm_flashinfer_bt8192|vllm|flashinfer|vLLM flashinfer batched-8192|auto|8192|0.93|8192||||2"
  "vllm_flashinfer_mem0937|vllm|flashinfer|vLLM flashinfer gpu-mem-0.937|auto|4096|0.937|8192||||2"
  "sglang_flashinfer_mem080|sglang|flashinfer|SGLang flashinfer mem-0.80||||8192|0.80||0|2"
  "sglang_flashinfer_mem090|sglang|flashinfer|SGLang flashinfer mem-0.90||||8192|0.90||0|2"
  "sglang_flashinfer_chunk4096|sglang|flashinfer|SGLang flashinfer chunk-4096||||8192|0.85|4096|0|2"
  "sglang_flashinfer_no_cuda_graph|sglang|flashinfer|SGLang flashinfer no-cuda-graph||||8192|0.85||1|2"
)

all_configs=()
case "$MODE" in
  phase1) all_configs=("${PHASE1_CONFIGS[@]}") ;;
  tuning) all_configs=("${TUNING_CONFIGS[@]}") ;;
  all) all_configs=("${PHASE1_CONFIGS[@]}" "${TUNING_CONFIGS[@]}") ;;
  *) echo "unsupported MODE=$MODE (phase1|tuning|all)" >&2; exit 2 ;;
esac

stop_containers() {
  docker rm -f "$VLLM_CONTAINER" >/dev/null 2>&1 || true
  docker rm -f "$SGLANG_CONTAINER" >/dev/null 2>&1 || true
}

init_outputs() {
  rm -rf "$LOG_DIR" "$RESP_DIR"
  mkdir -p "$RESULTS_ROOT" "$LOG_DIR" "$RESP_DIR"
  rm -f "$SUMMARY_CSV" "$SUMMARY_MD" "$REQUESTS_CSV"
  cat > "$REQUESTS_CSV" <<'EOF'
config_id,framework,backend,label,workload,prompt_tokens,max_tokens,run_index,elapsed_ms,completion_tokens,total_tokens,tok_per_s,status
EOF
  cat > "$SUMMARY_CSV" <<'EOF'
config_id,framework,backend,label,workload,prompt_tokens,max_tokens,warmup_runs_excluded,measured_runs,kv_cache_dtype,max_num_batched_tokens,gpu_memory_utilization,context_length,mem_fraction_static,chunked_prefill_size,disable_cuda_graph,status,median_elapsed_ms,median_tok_per_s,startup_seconds,notes
EOF
}

start_vllm() {
  local config_id="$1" backend="$2" kv_dtype="$3" max_batched="$4" gpu_mem="$5" context_len="$6"
  local backend_flags=""
  if [ "$backend" != "auto" ]; then
    backend_flags="--attention-backend $backend"
  fi
  local serve_cmd="pip install pytest -q && vllm serve $MODEL \
    --dtype auto \
    --kv-cache-dtype $kv_dtype \
    $backend_flags \
    --max-num-batched-tokens $max_batched \
    --max-model-len $context_len \
    --gpu-memory-utilization $gpu_mem \
    --enforce-eager"
  docker run -d \
    --name "$VLLM_CONTAINER" \
    --gpus all \
    -p "$VLLM_PORT:8000" \
    -v /home/ubuntu/.cache/huggingface:/root/.cache/huggingface \
    --shm-size 1g \
    -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
    --entrypoint bash \
    vllm/vllm-openai:nightly \
    -lc "$serve_cmd" >/dev/null

  local log_file="$LOG_DIR/${config_id}_startup.log"
  local elapsed=0
  while [ "$elapsed" -lt "$STARTUP_TIMEOUT" ]; do
    docker logs "$VLLM_CONTAINER" >"$log_file" 2>&1 || true
    if grep -q "startup complete" "$log_file"; then
      echo "$elapsed"
      return 0
    fi
    if grep -qE "OutOfMemoryError|CUDA out of memory|No available memory|Engine core initialization failed|Traceback" "$log_file"; then
      echo "$elapsed"
      return 1
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  echo "$elapsed"
  return 1
}

start_sglang() {
  local config_id="$1" backend="$2" context_len="$3" mem_fraction="$4" chunked_prefill="$5" disable_cuda_graph="$6"
  local args=(
    python3 -m sglang.launch_server
    --model-path "$MODEL"
    --host 0.0.0.0
    --port 30000
    --context-length "$context_len"
    --mem-fraction-static "$mem_fraction"
    --enable-metrics
  )
  if [ "$backend" != "auto" ]; then
    args+=(--attention-backend "$backend")
  fi
  if [ -n "$chunked_prefill" ]; then
    args+=(--chunked-prefill-size "$chunked_prefill")
  fi
  if [ "$disable_cuda_graph" = "1" ]; then
    args+=(--disable-cuda-graph)
  fi

  docker run -d \
    --name "$SGLANG_CONTAINER" \
    --gpus all \
    --shm-size 32g \
    --ipc=host \
    -p "$SGLANG_PORT:30000" \
    -v /home/ubuntu/.cache/huggingface:/root/.cache/huggingface \
    lmsysorg/sglang:latest \
    "${args[@]}" >/dev/null

  local log_file="$LOG_DIR/${config_id}_startup.log"
  local elapsed=0
  while [ "$elapsed" -lt "$STARTUP_TIMEOUT" ]; do
    docker logs "$SGLANG_CONTAINER" >"$log_file" 2>&1 || true
    if curl -fsS "http://127.0.0.1:$SGLANG_PORT/health" >/dev/null 2>&1; then
      echo "$elapsed"
      return 0
    fi
    if grep -qE "OutOfMemoryError|CUDA out of memory|RuntimeError|Traceback|ValueError" "$log_file"; then
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
  local config_id="$1" framework="$2" backend="$3" label="$4" workload="$5" max_tokens="$6" prompt_file="$7"
  local port url
  if [ "$framework" = "vllm" ]; then
    port="$VLLM_PORT"
  else
    port="$SGLANG_PORT"
  fi
  url="http://127.0.0.1:$port/v1/chat/completions"
  local response_dir="$RESP_DIR/${config_id}_${workload}"
  local summary_json="$response_dir/summary.json"

  python3 "$SCRIPT_DIR/bench_request.py" \
    --url "$url" \
    --model "$MODEL" \
    --prompt-file "$prompt_file" \
    --max-tokens "$max_tokens" \
    --runs "$RUNS" \
    --warmup-runs "$WARMUP_RUNS" \
    --timeout "$REQUEST_TIMEOUT" \
    --response-dir "$response_dir" \
    --summary-json "$summary_json" >/dev/null

  python3 - "$summary_json" "$REQUESTS_CSV" "$config_id" "$framework" "$backend" "$label" "$workload" <<'PY'
import csv, json, sys
summary_json, requests_csv, config_id, framework, backend, label, workload = sys.argv[1:]
data = json.load(open(summary_json, encoding='utf-8'))
with open(requests_csv, 'a', encoding='utf-8', newline='') as f:
    w = csv.writer(f)
    for r in data['runs']:
        w.writerow([
            config_id, framework, backend, label, workload, r.get('prompt_tokens', data.get('prompt_tokens', 0)),
            data['max_tokens'], r['run_index'], r['elapsed_ms'], r['completion_tokens'],
            r.get('total_tokens', 0), f"{r['tok_per_s']:.4f}", 'ok'
        ])
print(f"{data.get('prompt_tokens', 0)},{data['median_elapsed_ms']},{data['median_tok_per_s']}")
PY
}

generate_markdown() {
  python3 - "$SUMMARY_CSV" "$SUMMARY_MD" <<'PY'
import csv, sys
summary_csv, summary_md = sys.argv[1:]
rows = list(csv.DictReader(open(summary_csv, encoding='utf-8')))
with open(summary_md, 'w', encoding='utf-8') as out:
    out.write('# Backend Benchmark Summary\n\n')
    out.write('warmup runs are excluded from measured medians.\n\n')
    out.write('| config | framework | backend | workload | prompt tokens | status | median tok/s | median elapsed ms | notes |\n')
    out.write('|---|---|---|---|---:|---|---:|---:|---|\n')
    for r in rows:
        tok = f"{float(r['median_tok_per_s']):.2f}" if r['median_tok_per_s'] else ''
        elapsed = f"{float(r['median_elapsed_ms']):.1f}" if r['median_elapsed_ms'] else ''
        out.write(f"| {r['config_id']} | {r['framework']} | {r['backend']} | {r['workload']} | {r['prompt_tokens']} | {r['status']} | {tok} | {elapsed} | {r['notes']} |\n")
PY
}

if [ "$DRY_RUN" = "--dry-run" ]; then
  for config in "${all_configs[@]}"; do
    IFS='|' read -r config_id framework backend label kv_dtype max_batched gpu_mem context_len mem_fraction chunked_prefill disable_cuda_graph priority <<<"$config"
    echo "== $config_id: $label =="
  done
  exit 0
fi

init_outputs
trap 'stop_containers' EXIT

for config in "${all_configs[@]}"; do
  IFS='|' read -r config_id framework backend label kv_dtype max_batched gpu_mem context_len mem_fraction chunked_prefill disable_cuda_graph priority <<<"$config"
  echo "== $config_id: $label =="
  stop_containers
  startup_seconds=""
  status="ok"
  notes=""
  if [ "$framework" = "vllm" ]; then
    if ! startup_seconds="$(start_vllm "$config_id" "$backend" "$kv_dtype" "$max_batched" "$gpu_mem" "$context_len")"; then
      status="startup_failed"
      notes="see logs/${config_id}_startup.log"
    fi
  else
    if ! startup_seconds="$(start_sglang "$config_id" "$backend" "$context_len" "$mem_fraction" "$chunked_prefill" "$disable_cuda_graph")"; then
      status="startup_failed"
      notes="see logs/${config_id}_startup.log"
    fi
  fi

  for workload_def in "${WORKLOADS[@]}"; do
    IFS='|' read -r workload max_tokens prompt_file <<<"$workload_def"
    prompt_tokens=""
    median_elapsed=""
    median_tps=""
    if [ "$status" = "ok" ]; then
      if result="$(run_workload "$config_id" "$framework" "$backend" "$label" "$workload" "$max_tokens" "$prompt_file")"; then
        prompt_tokens="${result%%,*}"
        rest="${result#*,}"
        median_elapsed="${rest%,*}"
        median_tps="${rest#*,}"
      else
        status="request_failed"
        notes="see responses/${config_id}_${workload}"
      fi
    fi
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$config_id" "$framework" "$backend" "$label" "$workload" "$prompt_tokens" "$max_tokens" "$WARMUP_RUNS" "$RUNS" \
      "$kv_dtype" "$max_batched" "$gpu_mem" "$context_len" "$mem_fraction" "$chunked_prefill" "$disable_cuda_graph" \
      "$status" "$median_elapsed" "$median_tps" "$startup_seconds" "$notes" >>"$SUMMARY_CSV"
  done

  docker logs "$([ "$framework" = "vllm" ] && echo "$VLLM_CONTAINER" || echo "$SGLANG_CONTAINER")" >"$LOG_DIR/${config_id}_final.log" 2>&1 || true
  stop_containers
  sleep 3
done

generate_markdown
printf 'summary: %s\n' "$SUMMARY_MD"
