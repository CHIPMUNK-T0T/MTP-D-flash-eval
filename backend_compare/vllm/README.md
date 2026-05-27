# vLLM Backend Compare Design

## 比較したいこと

Qwen3.5-4B FP8 で、vLLM の attention backend を固定指定したときに decode 速度が変わるかを見る。

比較対象。

| ID | backend | 指定 |
|---|---|---|
| V0 | auto | `--attention-backend` なし |
| V1 | FlashAttention | `--attention-backend flash_attn` |
| V2 | FlashInfer | `--attention-backend flashinfer` |
| V3 | Triton | `--attention-backend triton_attn` |

RTX 4070 は SM 8.x 系なので、vLLM 公式の CUDA priority では標準 attention は `FLASH_ATTN` -> `FLASHINFER` -> `TRITON_ATTN` の順で自動選択される想定。

## 起動テンプレート

既存 `docker_vllm/mtp/qwen35-2b-fp8.sh` をベースにする。

```bash
BACKEND=flash_attn
docker run -d \
  --name vllm-backend-compare \
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
    --attention-backend ${BACKEND} \
    --max-num-batched-tokens 4096 \
    --max-model-len 2048 \
    --gpu-memory-utilization 0.93"
```

`auto` 条件では `--attention-backend ${BACKEND}` を外す。

## Phase 0: smoke

各 backend で以下を確認する。

- container が起動する
- `/health` が通る
- 32 tokens の chat completion が返る
- `docker logs` に選択 backend が出ている
- `/metrics` が取れる

起動しない場合は、その backend は `unsupported` として記録する。

## Phase 1: backend 固定比較

固定する値。

| 項目 | 値 |
|---|---|
| model | `RedHatAI/Qwen3.5-4B-FP8-dynamic` |
| dtype | `auto` |
| max model len | `2048` |
| max num batched tokens | `4096` |
| gpu memory utilization | `0.93` |
| enforce eager | `--enforce-eager` |
| concurrency | `1` |

workload。

| workload | prompt | max_tokens |
|---|---|---:|
| medium | `docker_vllm/prompts/medium.txt` | 256 |
| long | `docker_vllm/prompts/long.txt` | 512 |

各条件で warmup 1 回、測定 5 回、median tok/s を採用する。

## Phase 2: tuning matrix

Phase 1 の最速 backend を中心に、次を振る。

| 軸 | 候補 |
|---|---|
| `--max-num-batched-tokens` | `2048`, `4096`, `8192` |
| `--kv-cache-dtype` | `auto`, `fp8`, `fp8_e4m3` |
| CUDA graph | default, `--enforce-eager` |
| `--gpu-memory-utilization` | `0.90`, `0.93`, `0.937` |

優先順位は `max-num-batched-tokens`、KV cache dtype、CUDA graph、GPU memory utilization の順。

## ログで見るポイント

- 実際に選ばれた attention backend
- FlashInfer 指定時に FlashInfer import/install 問題が出ていないか
- Triton 指定時に JIT 初回だけ遅くなっていないか
- CUDA graph capture の有無
- OOM または fallback
- Qwen3.5 の GDN/linear attention 実装名

## 結果の読み方

backend 差が小さい場合、Qwen3.5-4B FP8 では attention よりも GDN/MLP/GEMM や scheduler overhead が支配的な可能性がある。

backend 差が大きい場合は、Medium と Long のどちらで効いたかを見る。prefill 寄りなら Medium/Long の初期遅延、decode 寄りなら長い生成で差が伸びる。
