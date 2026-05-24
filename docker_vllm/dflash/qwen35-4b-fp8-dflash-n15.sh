#!/bin/bash
# Qwen3.5-4B FP8 + D-Flash
# target: RedHatAI/Qwen3.5-4B-FP8-dynamic
# drafter: z-lab/Qwen3.5-4B-DFlash
# 4B は RTX 4070 12GB では CUDA graph が OOM になるため --enforce-eager 前提。

NUM_SPECULATIVE_TOKENS="${NUM_SPECULATIVE_TOKENS:-15}"
MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-4096}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-2048}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.937}"

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
  -c "pip install pytest -q && vllm serve RedHatAI/Qwen3.5-4B-FP8-dynamic \
    --dtype auto \
    --speculative-config '{\"method\": \"dflash\", \"model\": \"z-lab/Qwen3.5-4B-DFlash\", \"num_speculative_tokens\": ${NUM_SPECULATIVE_TOKENS}}' \
    --attention-backend flash_attn \
    --max-num-batched-tokens ${MAX_NUM_BATCHED_TOKENS} \
    --max-model-len ${MAX_MODEL_LEN} \
    --gpu-memory-utilization ${GPU_MEMORY_UTILIZATION} \
    --enforce-eager"
