# Backend Benchmark Plan

目的は、Qwen3.5-4B FP8 で backend と周辺 tuning のどれが速度に効くかを分離して見ること。

## 測定ルール

- 各 config ごとに Docker server を起動する。
- 起動直後は cold start / JIT / cache warmup が混ざるため、各 workload で `WARMUP_RUNS=1` を実行し、測定値から除外する。
- 測定は `RUNS=5`、集計は median。
- 最初は concurrency 1 に固定する。
- `temperature=0` と `enable_thinking=false` に固定する。
- smoke の tok/s は使わず、本 runner の measured runs だけを比較する。
- workload は `short_ctx512`、`mid_ctx2048`、`long_ctx8192` の 3 段にする。実際の入力長は API の `usage.prompt_tokens` を CSV に保存して確認する。
- 各 server は `context_length=8192` で起動し、短文と長文で起動条件が変わらないようにする。
- 過去の `long_ctx8192` 失敗結果は削除しない。同一入力でも vLLM と SGLang で token 数が変わる観測として、`results/benchmark/token_accounting_note.md` に残す。

## Phase 1: backend 単体比較

backend 以外をなるべく固定する。

| config | framework | backend | 主な固定条件 |
|---|---|---|---|
| `vllm_flash_attn` | vLLM | `flash_attn` | eager, KV auto, batched 4096, context 8192 |
| `vllm_flashinfer` | vLLM | `flashinfer` | eager, KV auto, batched 4096, context 8192 |
| `vllm_triton_attn` | vLLM | `triton_attn` | eager, KV auto, batched 4096, context 8192 |
| `sglang_flashinfer` | SGLang | `flashinfer` | CUDA graph default, mem 0.85, context 8192 |
| `sglang_triton` | SGLang | `triton` | CUDA graph default, mem 0.85, context 8192 |

SGLang `fa3` は default CUDA graph で失敗し、`--disable-cuda-graph` が必要だったため、Phase 1 の主比較から外す。

## Phase 2: load / concurrency 比較

Phase 1 の結果を残したまま、全 backend に対して concurrency を上げる。

目的は単発 decode 速度ではなく、RTX 4070 12GB という VRAM 制約下で、runtime / backend ごとの batching、scheduling、KV cache 圧迫、OOM 境界を観測すること。

デフォルト matrix は以下。

| 軸 | 値 |
|---|---|
| vLLM backend | `flash_attn`, `flashinfer`, `triton_attn` |
| SGLang backend | `flashinfer`, `triton` |
| concurrency | `1`, `2`, `4`, `8` |
| cases | concurrency ごとに per-request prompt 長を調整 |
| total cases | 5 backend x 4 concurrency = 20 |

concurrency ごとの load case は以下。各 case は active token budget が 8192 近辺になるように狙う。

| case | concurrency | max tokens | prompt |
|---|---:|---:|---|
| `c1_limit_8k` | 1 | 512 | `ctx8192.txt` full |
| `c2_limit_8k_each` | 2 | 512 | `ctx8192.txt` first 17000 chars; measured about 7395 prompt tokens |
| `c4_4k_each` | 4 | 512 | `ctx8192.txt` first 7300 chars; measured about 4323 prompt tokens |
| `c8_2k_each` | 8 | 256 | `ctx8192.txt` first 3700 chars; measured about 2189 prompt tokens |

実際の token 数は runtime により変わるため、CSV には API の `usage.prompt_tokens` を保存する。

測定指標。

- aggregate tok/s
- request p95 latency
- request median latency
- per-request tok/s
- success / failure count
- peak VRAM / GPU utilization
- startup failure / request failure / OOM 兆候

## Phase 3: tuning 比較

Phase 2 の結果を見てから、最速候補または安定候補を中心に 1 軸ずつ変える。現 runner には以下の候補を入れている。

| config | 目的 |
|---|---|
| `vllm_flashinfer_kvfp8` | vLLM で KV cache FP8 が効くか |
| `vllm_flashinfer_bt2048` | `--max-num-batched-tokens 2048` の影響 |
| `vllm_flashinfer_bt8192` | `--max-num-batched-tokens 8192` の影響 |
| `vllm_flashinfer_mem0937` | RTX 4070 の上限寄り memory utilization |
| `sglang_flashinfer_mem080` | SGLang の静的メモリを下げた場合 |
| `sglang_flashinfer_mem090` | SGLang の静的メモリを上げた場合 |
| `sglang_flashinfer_chunk4096` | chunked prefill size の影響 |
| `sglang_flashinfer_no_cuda_graph` | CUDA graph 無効化の影響 |

## 実行コマンド

構成確認のみ。

```bash
bash backend_compare/benchmark_backend.sh --dry-run
```

Phase 1 の本計測。

```bash
bash backend_compare/run_phase1_valid.sh
```

`long_ctx8192` だけ。

```bash
bash backend_compare/run_phase1_long_only.sh
```

Phase 2 の負荷テスト。

```bash
bash backend_compare/run_phase2_load.sh
```

Phase 2 の構成確認のみ。

```bash
bash backend_compare/run_phase2_load.sh --dry-run
```

共通 runner を直接使う場合。

```bash
MODE=phase1 RUNS=5 WARMUP_RUNS=1 bash backend_compare/benchmark_backend.sh
WORKLOAD_FILTER=long_ctx8192 MODE=phase1 RUNS=5 WARMUP_RUNS=1 bash backend_compare/benchmark_backend.sh
MODE=tuning RUNS=5 WARMUP_RUNS=1 bash backend_compare/benchmark_backend.sh
RUNS=5 WARMUP_RUNS=1 bash backend_compare/benchmark_phase2_load.sh
CONFIG_FILTER=vllm_flashinfer CASE_FILTER=c8_1k_each bash backend_compare/benchmark_phase2_load.sh
```

## 出力

- `backend_compare/results/phase1_valid/`: 正規の 15 件。
- `backend_compare/results/phase1_overflow_reference/`: 旧 `long_ctx8192` 超過の 5 件と `token_accounting_note.md`。
- `backend_compare/results/phase2_load/`: 全 backend x concurrency `1/2/4/8` の負荷テスト。
- `backend_compare/results/oom/`: OOM / startup failure を残す場所。
