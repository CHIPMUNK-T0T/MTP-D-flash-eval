#!/bin/bash
# Qwen3.5-4B BF16 + D-Flash (z-lab)
# 参考スクリプト: RTX 4070 12GB では VRAM 不足で未成立。
# 動作確認済みは FP8 版 (qwen35-4b-fp8-dflash-n15.sh)。
# pip install pytest: vLLM nightly の依存解決 (Qwen3.5 系全般で必要)

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
  -c "pip install pytest -q && vllm serve Qwen/Qwen3.5-4B \
    --dtype auto \
    --speculative-config '{\"method\": \"dflash\", \"model\": \"z-lab/Qwen3.5-4B-DFlash\", \"num_speculative_tokens\": ${NUM_SPECULATIVE_TOKENS}}' \
    --attention-backend flash_attn \
    --max-num-batched-tokens ${MAX_NUM_BATCHED_TOKENS} \
    --max-model-len ${MAX_MODEL_LEN} \
    --gpu-memory-utilization ${GPU_MEMORY_UTILIZATION} \
    --enforce-eager"
