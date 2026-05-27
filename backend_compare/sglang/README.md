# SGLang Backend Compare Design

## 比較したいこと

Qwen3.5-4B FP8 で、SGLang の attention backend と Qwen3.5 固有の GDN/linear attention 周辺が速度にどれだけ効くかを見る。

比較対象。

| ID | backend | 指定 | 扱い |
|---|---|---|---|
| S0 | auto | `--attention-backend` なし | baseline |
| S1 | FlashInfer | `--attention-backend flashinfer` | 主比較 |
| S2 | Triton | `--attention-backend triton` | 主比較 |
| S3 | FA3 | `--attention-backend fa3` | RTX 4070 では起動確認候補 |

SGLang 公式ドキュメントでは、Ada など Hopper 以外の CUDA MHA モデルは FlashInfer が使えれば FlashInfer、なければ Triton に fallback する説明になっている。FA3 は Hopper 系の候補なので、RTX 4070 では成功しても同条件比較として慎重に扱う。

## Qwen3.5 固有の注意

SGLang docs では Qwen3.5 / Qwen3 Next などの GDN linear attention は `--attention-backend` ではなく、GDN/linear attention 用 backend が別に扱われる。まずは default のまま測り、その後で以下を確認する。

- `--linear-attn-backend`
- `--linear-attn-decode-backend`
- `--linear-attn-prefill-backend`

候補は docs 上では CUDA Triton と CuTe DSL。CuTe DSL は prefill 非対応の記載があるため、最初は Triton default を基準にする。

## 起動テンプレート

公式 Docker は `lmsysorg/sglang:latest`。共有メモリは SGLang docs の例に合わせて大きめにする。

```bash
BACKEND=flashinfer
docker run -d \
  --name sglang-backend-compare \
  --gpus all \
  --restart unless-stopped \
  --shm-size 32g \
  --ipc=host \
  -p 30000:30000 \
  -v /home/ubuntu/.cache/huggingface:/root/.cache/huggingface \
  lmsysorg/sglang:latest \
  python3 -m sglang.launch_server \
    --model-path RedHatAI/Qwen3.5-4B-FP8-dynamic \
    --host 0.0.0.0 \
    --port 30000 \
    --context-length 2048 \
    --attention-backend ${BACKEND}
```

`auto` 条件では `--attention-backend ${BACKEND}` を外す。

pre-quantized FP8 モデルとしてロードする前提なので、最初は `--quantization fp8` などの online quantization は付けない。起動ログで compressed tensors / model config の扱いが合わない場合だけ、SGLang の FP8 quantization 指定を別条件として試す。

## Phase 0: smoke

各 backend で以下を確認する。

- container が起動する
- `/health` または OpenAI API が応答する
- 32 tokens の chat completion が返る
- server log に実 backend が出る
- `fa3` が RTX 4070 で unsupported にならないか

## Phase 1: backend 固定比較

固定する値。

| 項目 | 値 |
|---|---|
| model | `RedHatAI/Qwen3.5-4B-FP8-dynamic` |
| context length | `--context-length 2048` |
| attention backend | `auto`, `flashinfer`, `triton`, `fa3` |
| quantization | なし |
| concurrency | `1` |

vLLM と同じ 2048 にしないと、VRAM と scheduler 条件がずれる。

## Phase 2: tuning matrix

Phase 1 の最速 backend を中心に、次を振る。

| 軸 | 候補 |
|---|---|
| `--chunked-prefill-size` | default, `2048`, `4096`, `-1` |
| `--mem-fraction-static` | default, `0.85`, `0.90` |
| radix cache | default, disable |
| CUDA graph | default, disable |
| KV cache dtype | `auto`, 可能なら `fp8_e4m3` |
| linear attention backend | default, `triton`, CuTe DSL が使える場合のみ decode 側 |
| FP8 GEMM backend | default, `triton` など help に出る候補 |

最初から全組み合わせにしない。backend 単体比較で差が出た後、1 軸ずつ変える。

## ログで見るポイント

- 実際の attention backend
- GDN/linear attention backend
- FP8 weight がどうロードされたか
- CUDA graph capture の有無
- radix cache / chunked prefill の有無
- fallback や unsupported backend の警告

## 結果の読み方

SGLang は Qwen3.5 の GDN/linear attention を別 backend として持つため、`--attention-backend` の差が小さくても「full attention 層が少ないから効きにくい」とは限らない。ログで layer 種別と backend を確認してから解釈する。

vLLM と横比較する場合は、同一モデル、同一 prompt、同一 max tokens、同一 context limit、同一 concurrency に揃え、API overhead と tokenization の差は caveat として残す。
