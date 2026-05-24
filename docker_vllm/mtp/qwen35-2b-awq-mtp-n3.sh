#!/bin/bash
# Qwen3.5-2B AWQ 4bit + qwen3_next_mtp (MTP 投機的デコーディング)
# モデル: QuantTrio/Qwen3.5-2B-AWQ

NUM_SPECULATIVE_TOKENS="${NUM_SPECULATIVE_TOKENS:-3}"
MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-4096}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-2048}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.93}"

docker run -d \
  --name vllm-server \
  --gpus all \
  --restart unless-stopped \
  -p 8000:8000 \
  -v /home/ubuntu/.cache/huggingface:/root/.cache/huggingface \
  --shm-size 1g \
  -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
  --entrypoint bash \
  vllm/vllm-openai:nightly \
  -c "pip install pytest -q && vllm serve QuantTrio/Qwen3.5-2B-AWQ \
    --dtype auto \
    --speculative-config '{\"method\": \"qwen3_next_mtp\", \"num_speculative_tokens\": ${NUM_SPECULATIVE_TOKENS}}' \
    --attention-backend flash_attn \
    --max-num-batched-tokens ${MAX_NUM_BATCHED_TOKENS} \
    --max-model-len ${MAX_MODEL_LEN} \
    --gpu-memory-utilization ${GPU_MEMORY_UTILIZATION}"
