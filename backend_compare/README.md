# RTX 4070 Attention Backend Compare

目的は RTX 4070 12GB 上で、Qwen3.5-4B FP8 の attention backend と周辺チューニングが decode 速度にどれだけ効くかを切り分けること。

対象は以下の 2 系統。

- `backend_compare/vllm/`: vLLM OpenAI server
- `backend_compare/sglang/`: SGLang OpenAI-compatible server

## 結論メモ

まず見るべき比較は、vLLM では `flash_attn` / `flashinfer` / `triton_attn`。RTX 4070 は Ada Lovelace なので vLLM の自動選択では `FLASH_ATTN` が優先される想定。

SGLang では `flashinfer` / `triton` を主軸にする。SGLang の `fa3` は FlashAttention 3 で、公式ドキュメント上は Hopper 系の既定候補として扱われるため、RTX 4070 では「起動できるかを確認する候補」に留める。

Qwen3.5 は GDN/linear attention を含むハイブリッド構成なので、通常の full attention backend だけでなく、SGLang では `--linear-attn-backend` 系、vLLM ではログ上の GDN/linear attention 実装も確認する。

## 共通条件

既存ベンチと比較しやすいよう、最初は以下に固定する。

| 項目 | 値 |
|---|---|
| GPU | RTX 4070 12GB |
| モデル | `RedHatAI/Qwen3.5-4B-FP8-dynamic` |
| API | OpenAI-compatible `/v1/chat/completions` |
| temperature | `0` |
| concurrency | `1` |
| warmup | 1 run |
| measured runs | 5 runs |
| 集計 | median |
| workloads | Medium 256 tokens / Long 512 tokens |
| prompt | 既存 `docker_vllm/prompts/medium.txt`, `docker_vllm/prompts/long.txt` |
| max model len | `2048` |
| GPU memory utilization | vLLM は `0.93` 起点 |

## 測定指標

最低限、以下を CSV に残す。

- framework
- framework version / container image digest
- model
- backend
- tuning flags
- workload
- output tokens
- elapsed ms
- tokens/s
- startup seconds
- peak VRAM
- status
- notes

追加で確認するもの。

- サーバ起動ログ上の実バックエンド名
- CUDA graph 有無
- KV cache dtype
- thinking 無効化の成否
- 出力品質の簡易チェック

## 実験フェーズ

### Phase 0: 起動確認

各 backend で 1 回だけ 32 tokens を生成し、起動可否とログ上の backend を確認する。

この段階で不成立の backend は、以後の速度比較には入れず `unsupported` として記録する。

### Phase 1: backend 単体比較

周辺チューニングは固定し、attention backend だけを変える。

| framework | backend 候補 |
|---|---|
| vLLM | `flash_attn`, `flashinfer`, `triton_attn` |
| SGLang | `flashinfer`, `triton`, `fa3` 起動確認 |

### Phase 2: load / concurrency 比較

全 backend に対して concurrency `1`, `2`, `4`, `8` を回す。concurrency ごとに per-request prompt 長を変え、active token budget が 8192 近辺になるようにする。

見る指標は aggregate tok/s、request p95 latency、success / failure count、peak VRAM、OOM や request failure の境界。

### Phase 3: tuning 比較

Phase 2 の結果を見てから、安定候補を中心に以下を 1 軸ずつ振る。

- `max-num-batched-tokens` / `chunked-prefill-size`: `2048`, `4096`, `8192`
- KV cache dtype: `auto`, 可能なら `fp8` / `fp8_e4m3`
- CUDA graph: default と disable/enforce eager 相当
- prefix/radix cache: concurrency 条件で影響を分離して確認

## 注意点

- FlashAttention / FlashInfer / Triton の名前が framework 間で一致しない。vLLM の `flash_attn` と SGLang の `fa3` は同一条件とは限らない。
- RTX 4070 は SM 8.9 なので、Hopper/Blackwell 前提の backend は起動失敗や fallback があり得る。
- Qwen3.5 は GDN/linear attention を含むため、通常 attention backend の差だけで全体速度差を説明しない。
- FP8 weight のロード方法が vLLM と SGLang で異なる可能性がある。SGLang は pre-quantized model に余計な online quantization を重ねない方針から始める。

## 調査ソース

- vLLM Attention Backend Feature Support: https://docs.vllm.ai/en/latest/design/attention_backends/
- vLLM Docker: https://docs.vllm.ai/en/v0.13.0/deployment/docker/
- SGLang Attention Backend: https://docs.sglang.io/docs/advanced_features/attention_backend
- SGLang Server Arguments: https://docs.sglang.io/docs/advanced_features/server_arguments
- SGLang Quantization: https://docs.sglang.io/docs/advanced_features/quantization
- SGLang Docker install: https://docs.sglang.io/docs/get-started/install

## Run Entry Points

上位フォルダからまとめて実行する入口は以下。

```bash
bash backend_compare/run_phase1_valid.sh
bash backend_compare/run_phase1_long_only.sh
bash backend_compare/run_phase2_load.sh
```

- `run_phase1_valid.sh`: 正規の Phase 1 比較を `results/phase1_valid/` に出力する。
- `run_phase1_long_only.sh`: `long_ctx8192` だけを `results/phase1_valid_long_only/` に出力する。
- `run_phase2_load.sh`: 全 backend で concurrency `1/2/4/8` の負荷テストを `results/phase2_load/` に出力する。
- `benchmark_backend.sh`: 共通 runner。本体の設定と CSV 出力を持つ。
- `benchmark_phase2_load.sh`: Phase 2 専用 runner。並列 request、aggregate throughput、p95 latency を記録する。

## Current Result Sets

- `results/phase1_valid/`: 正規の 15 件。vLLM 9 件、SGLang 6 件。
- `results/phase1_overflow_reference/`: 旧 `long_ctx8192` 超過の 5 件。token accounting 差の観測として保持する。
- `results/phase2_load/`: Phase 2 の負荷テスト結果。既存 Phase 1 とは分離して保存する。
- `results/oom/`: 将来の OOM / startup failure の保管先。

詳細は `backend_compare/benchmark_plan.md` を参照。
