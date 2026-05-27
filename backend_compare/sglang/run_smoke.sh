#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_ROOT="${RESULTS_ROOT:-$ROOT_DIR/backend_compare/results}"
LOG_DIR="$RESULTS_ROOT/logs/sglang"
OUT_DIR="$RESULTS_ROOT/sglang"

MODEL="${MODEL:-RedHatAI/Qwen3.5-4B-FP8-dynamic}"
BACKEND="${BACKEND:-flashinfer}"
PORT="${PORT:-30100}"
CONTAINER_NAME="${CONTAINER_NAME:-sglang-backend-compare}"
CONTEXT_LENGTH="${CONTEXT_LENGTH:-2048}"
MEM_FRACTION_STATIC="${MEM_FRACTION_STATIC:-0.85}"
MAX_TOKENS="${MAX_TOKENS:-32}"
DISABLE_CUDA_GRAPH="${DISABLE_CUDA_GRAPH:-0}"
PROMPT_FILE="${PROMPT_FILE:-$ROOT_DIR/docker_vllm/prompts/medium.txt}"
IMAGE="${IMAGE:-lmsysorg/sglang:latest}"

mkdir -p "$LOG_DIR" "$OUT_DIR"

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

backend_flags=()
if [ "$BACKEND" != "auto" ]; then
  backend_flags=(--attention-backend "$BACKEND")
fi

cuda_graph_flags=()
if [ "$DISABLE_CUDA_GRAPH" = "1" ]; then
  cuda_graph_flags=(--disable-cuda-graph)
fi

cmd=(
  python3 -m sglang.launch_server
  --model-path "$MODEL"
  --host 0.0.0.0
  --port 30000
  --context-length "$CONTEXT_LENGTH"
  --mem-fraction-static "$MEM_FRACTION_STATIC"
  --enable-metrics
  "${backend_flags[@]}"
  "${cuda_graph_flags[@]}"
)

docker run -d \
  --name "$CONTAINER_NAME" \
  --gpus all \
  --shm-size 32g \
  --ipc=host \
  -p "$PORT:30000" \
  -v /home/ubuntu/.cache/huggingface:/root/.cache/huggingface \
  "$IMAGE" \
  "${cmd[@]}" >/dev/null

startup_log="$LOG_DIR/${BACKEND}_startup.log"
timeout="${STARTUP_TIMEOUT:-900}"
elapsed=0
while [ "$elapsed" -lt "$timeout" ]; do
  docker logs "$CONTAINER_NAME" >"$startup_log" 2>&1 || true
  if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    break
  fi
  if grep -qE "OutOfMemoryError|CUDA out of memory|RuntimeError|Traceback|ValueError" "$startup_log"; then
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
