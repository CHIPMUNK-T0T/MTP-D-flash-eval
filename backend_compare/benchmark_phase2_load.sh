#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_ROOT="${RESULTS_ROOT:-$SCRIPT_DIR/results/phase2_load}"
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
REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-600}"
CASE_FILTER="${CASE_FILTER:-}"
CONFIG_FILTER="${CONFIG_FILTER:-}"
VLLM_PORT="${VLLM_PORT:-8010}"
SGLANG_PORT="${SGLANG_PORT:-30100}"
VLLM_CONTAINER="${VLLM_CONTAINER:-vllm-backend-compare}"
SGLANG_CONTAINER="${SGLANG_CONTAINER:-sglang-backend-compare}"

COMPARE_PROMPT_DIR="${COMPARE_PROMPT_DIR:-$SCRIPT_DIR/prompts}"

# case_id|concurrency|max_tokens|prompt_file|prompt_char_limit|active_budget_note
LOAD_CASES=(
  "c1_limit_8k|1|512|$COMPARE_PROMPT_DIR/ctx8192.txt|0|single request near 8192 context"
  "c2_limit_8k_each|2|512|$COMPARE_PROMPT_DIR/ctx8192.txt|17000|about 7395 prompt tokens per request; two parallel near-limit requests"
  "c4_4k_each|4|512|$COMPARE_PROMPT_DIR/ctx8192.txt|7300|about 4323 prompt tokens per request; four parallel requests"
  "c8_2k_each|8|256|$COMPARE_PROMPT_DIR/ctx8192.txt|3700|about 2189 prompt tokens per request; eight parallel requests"
)

if [ -n "$CASE_FILTER" ]; then
  filtered_cases=()
  for case_def in "${LOAD_CASES[@]}"; do
    IFS='|' read -r case_id _concurrency _max_tokens _prompt_file _prompt_char_limit _note <<<"$case_def"
    if [ "$case_id" = "$CASE_FILTER" ]; then
      filtered_cases+=("$case_def")
    fi
  done
  if [ "${#filtered_cases[@]}" -eq 0 ]; then
    echo "unsupported CASE_FILTER=$CASE_FILTER" >&2
    exit 2
  fi
  LOAD_CASES=("${filtered_cases[@]}")
fi

# id|framework|backend|label|kv_cache_dtype|max_batched|gpu_mem|context_len|mem_fraction|chunked_prefill|disable_cuda_graph|max_num_seqs|max_running_requests
CONFIGS=(
  "vllm_flash_attn|vllm|flash_attn|vLLM flash_attn|auto|4096|0.93|8192||||16|"
  "vllm_flashinfer|vllm|flashinfer|vLLM flashinfer|auto|4096|0.93|8192||||16|"
  "vllm_triton_attn|vllm|triton_attn|vLLM triton_attn|auto|4096|0.93|8192||||16|"
  "sglang_flashinfer|sglang|flashinfer|SGLang flashinfer||||8192|0.85||0||16"
  "sglang_triton|sglang|triton|SGLang triton||||8192|0.85||0||16"
)

if [ -n "$CONFIG_FILTER" ]; then
  filtered_configs=()
  for config in "${CONFIGS[@]}"; do
    IFS='|' read -r config_id _framework _backend _label _kv_dtype _max_batched _gpu_mem _context_len _mem_fraction _chunked_prefill _disable_cuda_graph _max_num_seqs _max_running_requests <<<"$config"
    if [ "$config_id" = "$CONFIG_FILTER" ]; then
      filtered_configs+=("$config")
    fi
  done
  if [ "${#filtered_configs[@]}" -eq 0 ]; then
    echo "unsupported CONFIG_FILTER=$CONFIG_FILTER" >&2
    exit 2
  fi
  CONFIGS=("${filtered_configs[@]}")
fi

stop_containers() {
  docker rm -f "$VLLM_CONTAINER" >/dev/null 2>&1 || true
  docker rm -f "$SGLANG_CONTAINER" >/dev/null 2>&1 || true
}

init_outputs() {
  rm -rf "$LOG_DIR" "$RESP_DIR"
  mkdir -p "$RESULTS_ROOT" "$LOG_DIR" "$RESP_DIR"
  rm -f "$SUMMARY_CSV" "$SUMMARY_MD" "$REQUESTS_CSV"
  cat > "$REQUESTS_CSV" <<'EOF'
config_id,framework,backend,label,case_id,concurrency,prompt_tokens,max_tokens,batch_index,request_index,elapsed_ms,completion_tokens,total_tokens,tok_per_s,status,error
EOF
  cat > "$SUMMARY_CSV" <<'EOF'
config_id,framework,backend,label,case_id,concurrency,prompt_char_limit,prompt_tokens,max_tokens,active_budget_note,warmup_runs_excluded,measured_runs,kv_cache_dtype,max_num_batched_tokens,gpu_memory_utilization,context_length,mem_fraction_static,chunked_prefill_size,disable_cuda_graph,max_num_seqs,max_running_requests,status,total_requests,success_count,failure_count,median_batch_elapsed_ms,p95_request_elapsed_ms,median_aggregate_tok_per_s,median_request_tok_per_s,gpu_peak_memory_mb,gpu_peak_util_pct,startup_seconds,notes
EOF
}

start_gpu_sampler() {
  local output_file="$1"
  (
    while true; do
      nvidia-smi --query-gpu=memory.used,utilization.gpu --format=csv,noheader,nounits 2>/dev/null || true
      sleep 1
    done
  ) >"$output_file" &
  GPU_SAMPLER_PID="$!"
}

stop_gpu_sampler() {
  local pid="$1"
  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
}

gpu_sampler_peak() {
  local input_file="$1"
  python3 - "$input_file" <<'PY2'
import sys
path = sys.argv[1]
peak_mem = 0
peak_util = 0
try:
    with open(path, encoding='utf-8') as f:
        for line in f:
            parts = [p.strip() for p in line.split(',')]
            if len(parts) < 2:
                continue
            try:
                peak_mem = max(peak_mem, int(float(parts[0])))
                peak_util = max(peak_util, int(float(parts[1])))
            except ValueError:
                pass
except FileNotFoundError:
    pass
print(f"{peak_mem},{peak_util}")
PY2
}

start_vllm() {
  local config_id="$1" backend="$2" kv_dtype="$3" max_batched="$4" gpu_mem="$5" context_len="$6" max_num_seqs="$7"
  local backend_flags=""
  if [ "$backend" != "auto" ]; then
    backend_flags="--attention-backend $backend"
  fi
  local serve_cmd="pip install pytest -q && vllm serve $MODEL \
    --dtype auto \
    --kv-cache-dtype $kv_dtype \
    $backend_flags \
    --max-num-batched-tokens $max_batched \
    --max-num-seqs $max_num_seqs \
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
  local config_id="$1" backend="$2" context_len="$3" mem_fraction="$4" chunked_prefill="$5" disable_cuda_graph="$6" max_running_requests="$7"
  local args=(
    python3 -m sglang.launch_server
    --model-path "$MODEL"
    --host 0.0.0.0
    --port 30000
    --context-length "$context_len"
    --mem-fraction-static "$mem_fraction"
    --max-running-requests "$max_running_requests"
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

run_case() {
  local config_id="$1" framework="$2" backend="$3" label="$4" case_id="$5" concurrency="$6" max_tokens="$7" prompt_file="$8" prompt_char_limit="$9"
  local port url
  if [ "$framework" = "vllm" ]; then
    port="$VLLM_PORT"
  else
    port="$SGLANG_PORT"
  fi
  url="http://127.0.0.1:$port/v1/chat/completions"
  local response_dir="$RESP_DIR/${config_id}_${case_id}"
  local summary_json="$response_dir/summary.json"

  python3 "$SCRIPT_DIR/bench_concurrent_requests.py" \
    --url "$url" \
    --model "$MODEL" \
    --prompt-file "$prompt_file" \
    --prompt-char-limit "$prompt_char_limit" \
    --max-tokens "$max_tokens" \
    --concurrency "$concurrency" \
    --runs "$RUNS" \
    --warmup-runs "$WARMUP_RUNS" \
    --timeout "$REQUEST_TIMEOUT" \
    --response-dir "$response_dir" \
    --summary-json "$summary_json" >/dev/null

  python3 - "$summary_json" "$REQUESTS_CSV" "$config_id" "$framework" "$backend" "$label" "$case_id" <<'PY'
import csv, json, sys
summary_json, requests_csv, config_id, framework, backend, label, case_id = sys.argv[1:]
data = json.load(open(summary_json, encoding='utf-8'))
with open(requests_csv, 'a', encoding='utf-8', newline='') as f:
    w = csv.writer(f)
    for batch in data['runs']:
        for r in batch['requests']:
            w.writerow([
                config_id, framework, backend, label, case_id, data['concurrency'],
                r.get('prompt_tokens', data.get('prompt_tokens', 0)), data['max_tokens'],
                batch['batch_index'], r['request_index'], r['elapsed_ms'],
                r['completion_tokens'], r.get('total_tokens', 0), f"{r['tok_per_s']:.4f}",
                r['status'], r.get('error', ''),
            ])
print(",".join(str(data.get(k, "")) for k in [
    "prompt_tokens", "status", "total_requests", "success_count", "failure_count",
    "median_batch_elapsed_ms", "p95_request_elapsed_ms", "median_aggregate_tok_per_s",
    "median_request_tok_per_s",
]))
PY
}

generate_markdown() {
  python3 - "$SUMMARY_CSV" "$SUMMARY_MD" <<'PY'
import csv, sys
summary_csv, summary_md = sys.argv[1:]
rows = list(csv.DictReader(open(summary_csv, encoding='utf-8')))
with open(summary_md, 'w', encoding='utf-8') as out:
    out.write('# Phase 2 Load Benchmark Summary\n\n')
    out.write('Warmup batches are excluded. Each measured batch sends concurrent OpenAI-compatible chat requests.\n\n')
    out.write('| config | framework | backend | case | conc | prompt tokens | status | success | fail | median aggregate tok/s | p95 request ms | median batch ms | peak VRAM MB |\n')
    out.write('|---|---|---|---|---:|---:|---|---:|---:|---:|---:|---:|---:|\n')
    for r in rows:
        agg = f"{float(r['median_aggregate_tok_per_s']):.2f}" if r['median_aggregate_tok_per_s'] else ''
        p95 = f"{float(r['p95_request_elapsed_ms']):.1f}" if r['p95_request_elapsed_ms'] else ''
        batch = f"{float(r['median_batch_elapsed_ms']):.1f}" if r['median_batch_elapsed_ms'] else ''
        out.write(f"| {r['config_id']} | {r['framework']} | {r['backend']} | {r['case_id']} | {r['concurrency']} | {r['prompt_tokens']} | {r['status']} | {r['success_count']} | {r['failure_count']} | {agg} | {p95} | {batch} | {r['gpu_peak_memory_mb']} |\n")
PY
}

if [ "$DRY_RUN" = "--dry-run" ]; then
  for config in "${CONFIGS[@]}"; do
    IFS='|' read -r config_id framework backend label kv_dtype max_batched gpu_mem context_len mem_fraction chunked_prefill disable_cuda_graph max_num_seqs max_running_requests <<<"$config"
    for case_def in "${LOAD_CASES[@]}"; do
      IFS='|' read -r case_id concurrency max_tokens prompt_file prompt_char_limit active_budget_note <<<"$case_def"
      echo "== $config_id / $case_id: $label, concurrency=$concurrency, max_tokens=$max_tokens, prompt_char_limit=$prompt_char_limit =="
    done
  done
  exit 0
fi

init_outputs
trap 'stop_containers' EXIT

for config in "${CONFIGS[@]}"; do
  IFS='|' read -r config_id framework backend label kv_dtype max_batched gpu_mem context_len mem_fraction chunked_prefill disable_cuda_graph max_num_seqs max_running_requests <<<"$config"
  echo "== $config_id: $label =="
  stop_containers
  startup_seconds=""
  startup_status="ok"
  startup_notes=""

  if [ "$framework" = "vllm" ]; then
    if ! startup_seconds="$(start_vllm "$config_id" "$backend" "$kv_dtype" "$max_batched" "$gpu_mem" "$context_len" "$max_num_seqs")"; then
      startup_status="startup_failed"
      startup_notes="see logs/${config_id}_startup.log"
    fi
  else
    if ! startup_seconds="$(start_sglang "$config_id" "$backend" "$context_len" "$mem_fraction" "$chunked_prefill" "$disable_cuda_graph" "$max_running_requests")"; then
      startup_status="startup_failed"
      startup_notes="see logs/${config_id}_startup.log"
    fi
  fi

  for case_def in "${LOAD_CASES[@]}"; do
    IFS='|' read -r case_id concurrency max_tokens prompt_file prompt_char_limit active_budget_note <<<"$case_def"
    prompt_tokens=""
    status="$startup_status"
    total_requests="0"
    success_count="0"
    failure_count="0"
    median_batch_elapsed=""
    p95_request_elapsed=""
    median_aggregate_tps=""
    median_request_tps=""
    gpu_peak_memory=""
    gpu_peak_util=""
    notes="$startup_notes"
    if [ "$startup_status" = "ok" ]; then
      sampler_file="$LOG_DIR/${config_id}_${case_id}_gpu_samples.csv"
      start_gpu_sampler "$sampler_file"
      sampler_pid="$GPU_SAMPLER_PID"
      if result="$(run_case "$config_id" "$framework" "$backend" "$label" "$case_id" "$concurrency" "$max_tokens" "$prompt_file" "$prompt_char_limit")"; then
        stop_gpu_sampler "$sampler_pid"
        IFS=',' read -r prompt_tokens status total_requests success_count failure_count median_batch_elapsed p95_request_elapsed median_aggregate_tps median_request_tps <<<"$result"
        if [ "$status" != "ok" ]; then
          notes="see responses/${config_id}_${case_id}"
        fi
      else
        stop_gpu_sampler "$sampler_pid"
        status="request_failed"
        notes="see responses/${config_id}_${case_id}"
      fi
      gpu_peak="$(gpu_sampler_peak "$sampler_file")"
      gpu_peak_memory="${gpu_peak%,*}"
      gpu_peak_util="${gpu_peak#*,}"
    fi
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$config_id" "$framework" "$backend" "$label" "$case_id" "$concurrency" "$prompt_char_limit" "$prompt_tokens" "$max_tokens" "$active_budget_note" \
      "$WARMUP_RUNS" "$RUNS" "$kv_dtype" "$max_batched" "$gpu_mem" "$context_len" "$mem_fraction" "$chunked_prefill" "$disable_cuda_graph" \
      "$max_num_seqs" "$max_running_requests" "$status" "$total_requests" "$success_count" "$failure_count" "$median_batch_elapsed" "$p95_request_elapsed" \
      "$median_aggregate_tps" "$median_request_tps" "$gpu_peak_memory" "$gpu_peak_util" "$startup_seconds" "$notes" >>"$SUMMARY_CSV"
  done

  docker logs "$([ "$framework" = "vllm" ] && echo "$VLLM_CONTAINER" || echo "$SGLANG_CONTAINER")" >"$LOG_DIR/${config_id}_final.log" 2>&1 || true
  stop_containers
  sleep 3
done

generate_markdown
printf 'summary: %s\n' "$SUMMARY_MD"
