#!/bin/bash
# Qwen3.5-2B BF16 (speculative decoding なし)

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
  -c "pip install pytest -q && vllm serve Qwen/Qwen3.5-2B \
    --dtype auto \
    --attention-backend flash_attn \
    --max-num-batched-tokens 4096 \
    --max-model-len 2048 \
    --gpu-memory-utilization 0.93"
