#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_ROOT="${RESULTS_ROOT:-$ROOT_DIR/backend_compare/results}"
LOG_DIR="$RESULTS_ROOT/logs/vllm"
OUT_DIR="$RESULTS_ROOT/vllm"

MODEL="${MODEL:-RedHatAI/Qwen3.5-4B-FP8-dynamic}"
BACKEND="${BACKEND:-flash_attn}"
PORT="${PORT:-8010}"
CONTAINER_NAME="${CONTAINER_NAME:-vllm-backend-compare}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-2048}"
MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-4096}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.93}"
KV_CACHE_DTYPE="${KV_CACHE_DTYPE:-auto}"
MAX_TOKENS="${MAX_TOKENS:-32}"
PROMPT_FILE="${PROMPT_FILE:-$ROOT_DIR/docker_vllm/prompts/medium.txt}"

mkdir -p "$LOG_DIR" "$OUT_DIR"

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

backend_flags=""
if [ "$BACKEND" != "auto" ]; then
  backend_flags="--attention-backend $BACKEND"
fi

serve_cmd="pip install pytest -q && vllm serve $MODEL \
  --dtype auto \
  --kv-cache-dtype $KV_CACHE_DTYPE \
  $backend_flags \
  --max-num-batched-tokens $MAX_NUM_BATCHED_TOKENS \
  --max-model-len $MAX_MODEL_LEN \
  --gpu-memory-utilization $GPU_MEMORY_UTILIZATION \
  --enforce-eager"

docker run -d \
  --name "$CONTAINER_NAME" \
  --gpus all \
  -p "$PORT:8000" \
  -v /home/ubuntu/.cache/huggingface:/root/.cache/huggingface \
  --shm-size 1g \
  -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
  --entrypoint bash \
  vllm/vllm-openai:nightly \
  -lc "$serve_cmd" >/dev/null

startup_log="$LOG_DIR/${BACKEND}_startup.log"
timeout="${STARTUP_TIMEOUT:-900}"
elapsed=0
while [ "$elapsed" -lt "$timeout" ]; do
  docker logs "$CONTAINER_NAME" >"$startup_log" 2>&1 || true
  if grep -q "startup complete" "$startup_log"; then
    break
  fi
  if grep -qE "OutOfMemoryError|CUDA out of memory|No available memory|Engine core initialization failed|Traceback" "$startup_log"; then
    echo "startup_failed:$BACKEND" | tee "$OUT_DIR/${BACKEND}_status.txt"
    exit 1
  fi
  sleep 5
  elapsed=$((elapsed + 5))
done

if [ "$elapsed" -ge "$timeout" ]; then
  echo "startup_timeout:$BACKEND" | tee "$OUT_DIR/${BACKEND}_status.txt"
  exit 1
fi

python3 "$ROOT_DIR/backend_compare/smoke_request.py" \
  --url "http://127.0.0.1:$PORT/v1/chat/completions" \
  --model "$MODEL" \
  --prompt-file "$PROMPT_FILE" \
  --max-tokens "$MAX_TOKENS" \
  --output-json "$OUT_DIR/${BACKEND}_response.json" \
  --output-text "$OUT_DIR/${BACKEND}_response.txt" \
  --summary "$OUT_DIR/${BACKEND}_summary.json"

curl -s "http://127.0.0.1:$PORT/metrics" >"$LOG_DIR/${BACKEND}_metrics.prom" || true
docker logs "$CONTAINER_NAME" >"$startup_log" 2>&1 || true

echo "ok:$BACKEND" | tee "$OUT_DIR/${BACKEND}_status.txt"
