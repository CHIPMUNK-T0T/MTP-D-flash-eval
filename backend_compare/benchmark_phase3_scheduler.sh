#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_ROOT="${RESULTS_ROOT:-$SCRIPT_DIR/results/phase3_scheduler}"
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
REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-900}"
CASE_SET="${CASE_SET:-core}"
CONFIG_SET="${CONFIG_SET:-baseline}"
CASE_FILTER="${CASE_FILTER:-}"
CONFIG_FILTER="${CONFIG_FILTER:-}"
VLLM_PORT="${VLLM_PORT:-8010}"
SGLANG_PORT="${SGLANG_PORT:-30100}"
VLLM_CONTAINER="${VLLM_CONTAINER:-vllm-backend-compare}"
SGLANG_CONTAINER="${SGLANG_CONTAINER:-sglang-backend-compare}"

COMPARE_PROMPT_DIR="${COMPARE_PROMPT_DIR:-$SCRIPT_DIR/prompts}"
P512="$COMPARE_PROMPT_DIR/ctx512.txt"
P8192="$COMPARE_PROMPT_DIR/ctx8192.txt"

# case_id|category|concurrency|max_tokens|prompt_specs|purpose
CORE_CASES=(
  "hom_c8_2k_each|homogeneous_stream|8|256|long2k:$P8192:3700:8|Phase2 c8 throughputをTTFTとITLに分解する"
  "mix_short6_long2_c8|mixed_stream|8|256|short:$P512:0:6;long2k:$P8192:3700:2|長いprefillが短い依頼のTTFT/p95を悪化させるかを見る"
  "prefill_heavy_c4_4k_each|prefill_pressure|4|128|long4k:$P8192:7300:4|入力処理が重い時のscheduler/prefill処理を見る"
  "decode_heavy_c8_short|decode_pressure|8|1024|short:$P512:0:8|出力生成が長い時のITLとdecode安定性を見る"
)

LATENCY_SCALE_CASES=(
  "hom_c1_8k|latency_scale|1|512|long8k:$P8192:0:1|単発near-limit時のTTFT/ITL基準値を見る"
  "hom_c2_8k_each|latency_scale|2|512|long8k:$P8192:17000:2|2並列near-limit時のTTFT/ITL劣化を見る"
  "hom_c4_4k_each|latency_scale|4|512|long4k:$P8192:7300:4|4並列時のprefill/decodeバランスを見る"
  "hom_c8_2k_each|latency_scale|8|256|long2k:$P8192:3700:8|8並列時のscheduler効率を見る"
)

if [ "$CASE_SET" = "core" ]; then
  CASES=("${CORE_CASES[@]}")
elif [ "$CASE_SET" = "latency_scale" ]; then
  CASES=("${LATENCY_SCALE_CASES[@]}")
elif [ "$CASE_SET" = "all" ]; then
  CASES=("${CORE_CASES[@]}" "${LATENCY_SCALE_CASES[@]}")
else
  echo "unsupported CASE_SET=$CASE_SET; use core, latency_scale, or all" >&2
  exit 2
fi

if [ -n "$CASE_FILTER" ]; then
  filtered_cases=()
  for case_def in "${CASES[@]}"; do
    IFS='|' read -r case_id _category _concurrency _max_tokens _prompt_specs _purpose <<<"$case_def"
    if [ "$case_id" = "$CASE_FILTER" ]; then
      filtered_cases+=("$case_def")
    fi
  done
  if [ "${#filtered_cases[@]}" -eq 0 ]; then
    echo "unsupported CASE_FILTER=$CASE_FILTER" >&2
    exit 2
  fi
  CASES=("${filtered_cases[@]}")
fi

# id|framework|backend|label|kv_cache_dtype|max_batched|gpu_mem|context_len|mem_fraction|chunked_prefill|disable_cuda_graph|max_num_seqs|max_running_requests|tuning_purpose
BASELINE_CONFIGS=(
  "vllm_flashinfer_base|vllm|flashinfer|vLLM flashinfer baseline|auto|4096|0.93|8192||||16||backend差を外しschedulerを見るためのvLLM代表"
  "sglang_flashinfer_base|sglang|flashinfer|SGLang flashinfer baseline||||8192|0.85||0||16|backend差を外しschedulerを見るためのSGLang代表"
)

TUNING_CONFIGS=(
  "vllm_flashinfer_seq8|vllm|flashinfer|vLLM flashinfer max_num_seqs=8|auto|4096|0.93|8192||||8||同時実行上限を下げて遅延安定性が上がるかを見る"
  "vllm_flashinfer_batch8192|vllm|flashinfer|vLLM flashinfer batched_tokens=8192|auto|8192|0.93|8192||||16||prefillを広く詰めた時の吞吐とp95を見る"
  "sglang_flashinfer_run8|sglang|flashinfer|SGLang flashinfer max_running=8||||8192|0.85||0||8|同時実行上限を下げて遅延安定性が上がるかを見る"
  "sglang_flashinfer_chunk4096|sglang|flashinfer|SGLang flashinfer chunked_prefill=4096||||8192|0.85|4096|0||16|chunked prefillで短い依頼のTTFTが守られるかを見る"
)

if [ "$CONFIG_SET" = "baseline" ]; then
  CONFIGS=("${BASELINE_CONFIGS[@]}")
elif [ "$CONFIG_SET" = "tuning" ]; then
  CONFIGS=("${TUNING_CONFIGS[@]}")
elif [ "$CONFIG_SET" = "all" ]; then
  CONFIGS=("${BASELINE_CONFIGS[@]}" "${TUNING_CONFIGS[@]}")
else
  echo "unsupported CONFIG_SET=$CONFIG_SET; use baseline, tuning, or all" >&2
  exit 2
fi

if [ -n "$CONFIG_FILTER" ]; then
  filtered_configs=()
  for config in "${CONFIGS[@]}"; do
    IFS='|' read -r config_id _framework _backend _label _kv_dtype _max_batched _gpu_mem _context_len _mem_fraction _chunked_prefill _disable_cuda_graph _max_num_seqs _max_running_requests _tuning_purpose <<<"$config"
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
  python3 - "$SUMMARY_CSV" "$REQUESTS_CSV" <<'PY'
import csv
import sys
summary_csv, requests_csv = sys.argv[1:]
with open(summary_csv, "w", encoding="utf-8", newline="") as f:
    csv.writer(f).writerow([
        "config_id", "framework", "backend", "label", "case_id", "category", "purpose",
        "concurrency", "max_tokens", "prompt_specs", "warmup_runs_excluded", "measured_runs",
        "kv_cache_dtype", "max_num_batched_tokens", "gpu_memory_utilization", "context_length",
        "mem_fraction_static", "chunked_prefill_size", "disable_cuda_graph", "max_num_seqs",
        "max_running_requests", "tuning_purpose", "status", "total_requests", "success_count",
        "failure_count", "median_aggregate_tok_per_s", "median_batch_elapsed_ms",
        "p50_ttft_ms", "p95_ttft_ms", "p50_itl_ms", "p95_itl_ms",
        "p50_request_elapsed_ms", "p95_request_elapsed_ms", "median_request_tok_per_s",
        "profile_summary_json", "gpu_peak_memory_mb", "gpu_peak_util_pct", "startup_seconds", "notes",
    ])
with open(requests_csv, "w", encoding="utf-8", newline="") as f:
    csv.writer(f).writerow([
        "config_id", "framework", "backend", "case_id", "category", "batch_index", "request_index",
        "profile", "status", "elapsed_ms", "ttft_ms", "mean_itl_ms", "p50_itl_ms", "p95_itl_ms",
        "prompt_tokens", "completion_tokens", "completion_units", "tok_per_s", "error",
    ])
PY
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
  python3 - "$input_file" <<'PY'
import sys
path = sys.argv[1]
peak_mem = 0
peak_util = 0
try:
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = [p.strip() for p in line.split(",")]
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
PY
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
  local config_id="$1" framework="$2" backend="$3" label="$4" case_id="$5" concurrency="$6" max_tokens="$7" prompt_specs="$8"
  local port url
  if [ "$framework" = "vllm" ]; then
    port="$VLLM_PORT"
  else
    port="$SGLANG_PORT"
  fi
  url="http://127.0.0.1:$port/v1/chat/completions"
  local response_dir="$RESP_DIR/${config_id}_${case_id}"
  local summary_json="$response_dir/summary.json"

  python3 "$SCRIPT_DIR/bench_streaming_concurrent.py" \
    --url "$url" \
    --model "$MODEL" \
    --prompt-specs "$prompt_specs" \
    --max-tokens "$max_tokens" \
    --concurrency "$concurrency" \
    --runs "$RUNS" \
    --warmup-runs "$WARMUP_RUNS" \
    --timeout "$REQUEST_TIMEOUT" \
    --response-dir "$response_dir" \
    --summary-json "$summary_json" >/dev/null
}

append_case_csv() {
  python3 - "$SUMMARY_CSV" "$REQUESTS_CSV" "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}" "${13}" "${14}" "${15}" "${16}" "${17}" "${18}" "${19}" "${20}" "${21}" "${22}" "${23}" "${24}" "${25}" <<'PY'
import csv
import json
import sys

(
    summary_csv, requests_csv, summary_json, config_id, framework, backend, label, case_id,
    category, purpose, concurrency, max_tokens, prompt_specs, kv_dtype, max_batched, gpu_mem,
    context_len, mem_fraction, chunked_prefill, disable_cuda_graph, max_num_seqs,
    max_running_requests, tuning_purpose, startup_seconds, gpu_peak_memory, gpu_peak_util, notes
) = sys.argv[1:]

if summary_json:
    data = json.load(open(summary_json, encoding="utf-8"))
else:
    data = {
        "status": "startup_failed",
        "total_requests": 0,
        "success_count": 0,
        "failure_count": 0,
        "median_aggregate_tok_per_s": "",
        "median_batch_elapsed_ms": "",
        "p50_ttft_ms": "",
        "p95_ttft_ms": "",
        "p50_itl_ms": "",
        "p95_itl_ms": "",
        "p50_request_elapsed_ms": "",
        "p95_request_elapsed_ms": "",
        "median_request_tok_per_s": "",
        "profile_summary": {},
        "runs": [],
    }

with open(summary_csv, "a", encoding="utf-8", newline="") as f:
    csv.writer(f).writerow([
        config_id, framework, backend, label, case_id, category, purpose, concurrency, max_tokens,
        prompt_specs, data.get("warmup_runs_excluded", ""), data.get("measured_runs", ""),
        kv_dtype, max_batched, gpu_mem, context_len, mem_fraction, chunked_prefill,
        disable_cuda_graph, max_num_seqs, max_running_requests, tuning_purpose,
        data.get("status", "request_failed"), data.get("total_requests", 0),
        data.get("success_count", 0), data.get("failure_count", 0),
        data.get("median_aggregate_tok_per_s", ""), data.get("median_batch_elapsed_ms", ""),
        data.get("p50_ttft_ms", ""), data.get("p95_ttft_ms", ""),
        data.get("p50_itl_ms", ""), data.get("p95_itl_ms", ""),
        data.get("p50_request_elapsed_ms", ""), data.get("p95_request_elapsed_ms", ""),
        data.get("median_request_tok_per_s", ""),
        json.dumps(data.get("profile_summary", {}), ensure_ascii=False),
        gpu_peak_memory, gpu_peak_util, startup_seconds, notes,
    ])

with open(requests_csv, "a", encoding="utf-8", newline="") as f:
    writer = csv.writer(f)
    for batch in data.get("runs", []):
        for r in batch.get("requests", []):
            writer.writerow([
                config_id, framework, backend, case_id, category, batch.get("batch_index", ""),
                r.get("request_index", ""), r.get("profile", ""), r.get("status", ""),
                r.get("elapsed_ms", ""), r.get("ttft_ms", ""), r.get("mean_itl_ms", ""),
                r.get("p50_itl_ms", ""), r.get("p95_itl_ms", ""), r.get("prompt_tokens", ""),
                r.get("completion_tokens", ""), r.get("completion_units", ""),
                r.get("tok_per_s", ""), r.get("message", ""),
            ])
PY
}

generate_markdown() {
  python3 - "$SUMMARY_CSV" "$SUMMARY_MD" <<'PY'
import csv
import sys
summary_csv, summary_md = sys.argv[1:]
rows = list(csv.DictReader(open(summary_csv, encoding="utf-8")))
with open(summary_md, "w", encoding="utf-8") as out:
    out.write("# Phase 3 Scheduler Benchmark Summary\n\n")
    out.write("目的: Phase 2で見えた並列負荷時の差を、streaming計測でTTFT・ITL・混在負荷・scheduler tuningに分解する。\n\n")
    out.write("Warmup batches are excluded. Streaming responses are used, so TTFT and ITL are measured from received chunks.\n\n")
    out.write("| config | case | purpose | conc | status | agg tok/s | p95 TTFT ms | p95 ITL ms | p95 req ms | peak VRAM MB |\n")
    out.write("|---|---|---|---:|---|---:|---:|---:|---:|---:|\n")
    for r in rows:
        def fmt(key):
            return f"{float(r[key]):.2f}" if r.get(key) else ""
        out.write(
            f"| {r['config_id']} | {r['case_id']} | {r['purpose']} | {r['concurrency']} | "
            f"{r['status']} | {fmt('median_aggregate_tok_per_s')} | {fmt('p95_ttft_ms')} | "
            f"{fmt('p95_itl_ms')} | {fmt('p95_request_elapsed_ms')} | {r['gpu_peak_memory_mb']} |\n"
        )
PY
}

write_readme() {
  cat > "$RESULTS_ROOT/README.md" <<'EOF'
# Phase 3 Scheduler / Streaming Latency

Phase 3は、Phase 2で見えた「並列時にSGLangが強い」という結果を、schedulerとbatchingの観点で分解するための実験です。

見るもの:
- TTFT: prefill待ち、queue待ち、chunked prefillの効き方
- ITL: decode中の安定性、token間隔のばらつき
- mixed workload: 長い入力が短い依頼を巻き込んで遅くするか
- tuning: 同時実行数やbatched token上限を変えると、throughputとp95 latencyがどう変わるか

デフォルト:
- `CONFIG_SET=baseline`: vLLM flashinfer と SGLang flashinfer
- `CASE_SET=core`: c8同質負荷、short/long混在、prefill重視、decode重視

拡張:
- `CASE_SET=latency_scale`: c1/c2/c4/c8の同質負荷でスケールを見る
- `CONFIG_SET=tuning`: scheduler系パラメータだけを見る
- `CONFIG_SET=all CASE_SET=all`: 全部回す

実行例:
- `bash backend_compare/run_phase3_scheduler.sh --dry-run`
- `CASE_SET=core CONFIG_SET=baseline bash backend_compare/run_phase3_scheduler.sh`
- `CASE_FILTER=mix_short6_long2_c8 CONFIG_SET=tuning bash backend_compare/run_phase3_scheduler.sh`

出力:
- `summary.csv`: config x caseの集約結果
- `requests.csv`: request単位のTTFT/ITL/elapsed
- `summary.md`: 記事用に読みやすい集約
- `responses/`: streaming eventと生成テキスト
- `logs/`: startup logとGPU samples

注: streamingレスポンスでusageが返らない場合、tok/sは受信したcontent chunk数ベースの近似になります。TTFT/ITLはそのまま比較できます。
EOF
}

if [ "$DRY_RUN" = "--dry-run" ]; then
  for config in "${CONFIGS[@]}"; do
    IFS='|' read -r config_id framework backend label kv_dtype max_batched gpu_mem context_len mem_fraction chunked_prefill disable_cuda_graph max_num_seqs max_running_requests tuning_purpose <<<"$config"
    for case_def in "${CASES[@]}"; do
      IFS='|' read -r case_id category concurrency max_tokens prompt_specs purpose <<<"$case_def"
      echo "== $config_id / $case_id =="
      echo "framework=$framework backend=$backend concurrency=$concurrency max_tokens=$max_tokens"
      echo "purpose=$purpose"
      echo "prompt_specs=$prompt_specs"
      echo "tuning=$tuning_purpose"
    done
  done
  exit 0
fi

init_outputs
write_readme
trap 'stop_containers' EXIT

for config in "${CONFIGS[@]}"; do
  IFS='|' read -r config_id framework backend label kv_dtype max_batched gpu_mem context_len mem_fraction chunked_prefill disable_cuda_graph max_num_seqs max_running_requests tuning_purpose <<<"$config"
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

  for case_def in "${CASES[@]}"; do
    IFS='|' read -r case_id category concurrency max_tokens prompt_specs purpose <<<"$case_def"
    summary_json=""
    gpu_peak_memory=""
    gpu_peak_util=""
    notes="$startup_notes"
    if [ "$startup_status" = "ok" ]; then
      sampler_file="$LOG_DIR/${config_id}_${case_id}_gpu_samples.csv"
      start_gpu_sampler "$sampler_file"
      sampler_pid="$GPU_SAMPLER_PID"
      response_dir="$RESP_DIR/${config_id}_${case_id}"
      summary_json="$response_dir/summary.json"
      if ! run_case "$config_id" "$framework" "$backend" "$label" "$case_id" "$concurrency" "$max_tokens" "$prompt_specs"; then
        notes="see responses/${config_id}_${case_id}"
      fi
      stop_gpu_sampler "$sampler_pid"
      gpu_peak="$(gpu_sampler_peak "$sampler_file")"
      gpu_peak_memory="${gpu_peak%,*}"
      gpu_peak_util="${gpu_peak#*,}"
      if [ ! -f "$summary_json" ]; then
        summary_json=""
      fi
    fi
    append_case_csv "$summary_json" "$config_id" "$framework" "$backend" "$label" "$case_id" "$category" "$purpose" \
      "$concurrency" "$max_tokens" "$prompt_specs" "$kv_dtype" "$max_batched" "$gpu_mem" "$context_len" "$mem_fraction" \
      "$chunked_prefill" "$disable_cuda_graph" "$max_num_seqs" "$max_running_requests" "$tuning_purpose" "$startup_seconds" \
      "$gpu_peak_memory" "$gpu_peak_util" "$notes"
  done

  docker logs "$([ "$framework" = "vllm" ] && echo "$VLLM_CONTAINER" || echo "$SGLANG_CONTAINER")" >"$LOG_DIR/${config_id}_final.log" 2>&1 || true
  stop_containers
  sleep 3
done

generate_markdown
printf 'summary: %s\n' "$SUMMARY_MD"
