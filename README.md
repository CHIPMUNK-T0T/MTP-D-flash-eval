# Qwen3.5 vLLM Speculative Decoding Benchmark

Qwen3.5 のローカル推論で、MTP と D-Flash による速度変化を測ったリポジトリです。  
RTX 4070 12GB 上で動かすことを前提にしています。

主に次の2つを評価しています。

- Qwen3.5-2B の `qwen3_next_mtp`
- Qwen3.5-4B FP8 の D-Flash と MTP 比較
- 上記の日本語プロンプト版と英語プロンプト版の比較

Qiita 記事用のドラフトは以下です。

- `Blog_draft_2b_part1.md`: Qwen3.5-2B FP16 + MTP (記事①)
- `Blog_draft_2b_part2.md`: Qwen3.5-2B 全量子化 + MTP (記事②)
- `Blog_draft_dflash.md`: Qwen3.5-4B D-Flash vs MTP (記事③)
- `Blog_draft_english.md`: 日本語 vs 英語 acceptance rate 比較 (記事④)

## 環境

| 項目 | 内容 |
|---|---|
| GPU | RTX 4070 12GB |
| 実VRAM | 11.59 GiB |
| OS | Ubuntu |
| vLLM | `vllm/vllm-openai:nightly` |
| vLLM version | `v0.21.1rc1.dev243` |
| API | OpenAI compatible `/v1/chat/completions` |
| Thinking | `chat_template_kwargs.enable_thinking=false` |
| model cache | `/home/ubuntu/.cache/huggingface` |

Docker で vLLM を起動します。  
各スクリプトは `docker run -d --name vllm-server` でサーバを起動します。

既存の vLLM コンテナが残っている場合は先に止めます。

```bash
docker stop vllm-server
docker rm vllm-server
```

## ディレクトリ構成

```text
docker_vllm/
  prompts/
    medium.txt        # 日本語プロンプト
    long.txt
  prompts/en/
    medium.txt        # 英語プロンプト
    long.txt

  mtp/
    benchmark_mtp_matrix.sh
    qwen35-2b-*.sh

  dflash/
    benchmark_dflash_4b.sh
    benchmark_4b_mtp_compare.sh
    qwen35-4b-*.sh

ollama/
  benchmark_ollama_qwen35_2b.sh
  Modelfile.qwen35-2b-bench

benchmark_mtp.sh          # 日本語 2B MTP
benchmark_dflash.sh       # 日本語 4B D-Flash/MTP
benchmark_ollama.sh       # 日本語 Ollama
benchmark_all.sh          # 上記3本を順に実行 + サマリー生成

benchmark_mtp_en.sh       # 英語 2B MTP
benchmark_dflash_en.sh    # 英語 4B D-Flash/MTP
benchmark_ollama_en.sh    # 英語 Ollama
benchmark_all_english.sh  # 英語版3本を順に実行 + サマリー生成

results/                  # 日本語プロンプトの結果
  summary.csv
  summary.md
  mtp/
  d-flash/
  ollama/
  logs/
  metrics/

results_english/          # 英語プロンプトの結果
  summary.csv
  summary.md
  mtp/
  d-flash/
  ollama/

ignore/
  過去メモ、古い試行ログ、未採用スクリプト
```

## 評価条件

全体で、比較対象以外の条件をなるべく揃えています。

| 項目 | 値 |
|---|---|
| temperature | 0 |
| concurrency | 1 |
| warmup | 1回 |
| measured runs | 5回 |
| 集計 | median |
| workloads | Medium / Long |
| vLLM thinking | `chat_template_kwargs.enable_thinking=false` |
| Ollama thinking | `think=false` |

workload は以下の2種類です。

| workload | 入力 | 出力 |
|---|---:|---:|
| Medium | 約100 tokens | 256 tokens |
| Long | 約200 tokens | 512 tokens |

### 条件を揃えた理由

`temperature=0` は、出力の揺れを減らして速度比較をしやすくするためです。

`concurrency=1` は、まず単一リクエストで decode がどれだけ速くなるかを見るためです。  
並列性能は別の評価軸になるため、今回は混ぜていません。

`max_model_len=2048` は、RTX 4070 12GB で 4B 構成を成立させるためです。  
Qwen3.5 は Mamba/GDN 系の固定 state や Vision Encoder のメモリ消費があり、単純な Transformer より VRAM 制約が出やすいです。

`max_num_batched_tokens=4096` は、2B と 4B の比較条件を揃えるためです。  
4B D-Flash では大きくしすぎるとメモリ面の余裕が減るため、2B 本番ベンチと同じ 4096 にしています。

4B では `--enforce-eager` を使っています。  
RTX 4070 12GB では CUDA graph capture の追加メモリで OOM になったため、baseline / D-Flash / MTP をすべて eager mode に揃えています。

## 2B MTP 評価

2B は以下の 3 系統で、MTP なし / n=1 / n=3 / n=5 を比較します。

| 量子化 | モデル |
|---|---|
| FP16 | `Qwen/Qwen3.5-2B` |
| FP8 | `lovedheart/Qwen3.5-2B-FP8` |
| AWQ4 | `QuantTrio/Qwen3.5-2B-AWQ` |

```text
docker_vllm/mtp/qwen35-2b-fp16.sh
docker_vllm/mtp/qwen35-2b-fp16-mtp-n1.sh
docker_vllm/mtp/qwen35-2b-fp16-mtp-n3.sh
docker_vllm/mtp/qwen35-2b-fp16-mtp-n5.sh

docker_vllm/mtp/qwen35-2b-fp8.sh
docker_vllm/mtp/qwen35-2b-fp8-mtp-n1.sh
docker_vllm/mtp/qwen35-2b-fp8-mtp-n3.sh
docker_vllm/mtp/qwen35-2b-fp8-mtp-n5.sh

docker_vllm/mtp/qwen35-2b-awq.sh
docker_vllm/mtp/qwen35-2b-awq-mtp-n1.sh
docker_vllm/mtp/qwen35-2b-awq-mtp-n3.sh
docker_vllm/mtp/qwen35-2b-awq-mtp-n5.sh
```

実行:

```bash
bash benchmark_mtp.sh           # 日本語
bash benchmark_mtp_en.sh        # 英語
```

ドライラン:

```bash
bash benchmark_mtp.sh --dry-run
```

出力:

```text
results/mtp/requests.csv
results/mtp/summary.csv
results/mtp/summary.md
results/mtp/review.md
results/mtp/responses/
results/logs/mtp/
results/metrics/mtp/
```

## 4B D-Flash / MTP 評価

4B は FP8 target に絞っています。

| ID | 構成 | モデル / method |
|---|---|---|
| D0 | baseline | `RedHatAI/Qwen3.5-4B-FP8-dynamic` |
| D1 | D-Flash n=15 | `z-lab/Qwen3.5-4B-DFlash` |
| D2 | MTP n=3 | `qwen3_next_mtp` |

RTX 4070 12GB では未成立でしたが、参考用に `Qwen/Qwen3.5-4B` の BF16 スクリプトも置いています。

```text
docker_vllm/dflash/qwen35-4b-fp8.sh
docker_vllm/dflash/qwen35-4b-fp8-dflash-n15.sh
docker_vllm/dflash/qwen35-4b-fp8-mtp-n3.sh
docker_vllm/dflash/qwen35-4b-fp16.sh              # 参考用 (12GB 未成立)
docker_vllm/dflash/qwen35-4b-fp16-dflash-n15.sh   # 参考用 (12GB 未成立)
```

```bash
bash benchmark_dflash.sh        # 日本語
bash benchmark_dflash_en.sh     # 英語
```

出力:

```text
results/d-flash/summary.csv
results/d-flash/summary.md
results/d-flash/mtp_summary.csv
results/d-flash/spec_compare.csv
results/d-flash/spec_compare.md
results/d-flash/review.md
results/d-flash/responses/
results/logs/d-flash/
results/metrics/d-flash/
```

## Ollama 参考値

vLLM とは API と tokenization が異なるため、参考値です。

```bash
bash benchmark_ollama.sh        # 日本語
bash benchmark_ollama_en.sh     # 英語
```

設定:

| 項目 | 値 |
|---|---|
| base model | `qwen3.5:2b` |
| local model | `qwen35-2b-bench` |
| quantization | Q8_0 |
| temperature | 0 |
| num_ctx | 2048 |
| API payload | `think: false` |

## 全実行

```bash
bash benchmark_all.sh           # 日本語: 2B MTP + 4B D-Flash/MTP + Ollama → results/
bash benchmark_all_english.sh   # 英語: 同構成 → results_english/
```

既存結果からサマリーだけ作り直す場合:

```bash
bash benchmark_all.sh --summary-only
bash benchmark_all_english.sh --summary-only
```

## 結果概要

全計測で `enable_thinking=false` を明示しています。

### 2B MTP ─ 日本語プロンプト

Medium は出力 256 tokens、Long は出力 512 tokens です。

| 量子化 | 構成 | Medium tok/s | Long tok/s | Long acceptance |
|---|---|---:|---:|---:|
| FP16 | baseline | 115.4 | 116.0 | - |
| FP16 | MTP n=1 | 126.4 | 133.5 | 0.602 |
| FP16 | MTP n=3 | 119.7 | 120.6 | 0.356 |
| FP16 | MTP n=5 | 94.3 | 91.1 | 0.207 |
| FP8 | baseline | 122.3 | 123.9 | - |
| FP8 | **MTP n=1** | **143.1** | **147.3** | **0.597** |
| FP8 | MTP n=3 | 112.6 | 131.1 | 0.362 |
| FP8 | MTP n=5 | 88.5 | 100.2 | 0.222 |
| AWQ4 | baseline | 161.9 | 164.1 | - |
| AWQ4 | MTP n=1 | 180.3 | 172.9 | 0.602 |
| AWQ4 | MTP n=3 | 151.0 | 140.5 | 0.340 |
| AWQ4 | MTP n=5 | 116.7 | 108.4 | 0.222 |

日本語では **n=1 だけが確実にプラス**。n=3 以上は量子化・workload によって baseline を下回ることがある。

### 2B MTP ─ 英語プロンプト

| 量子化 | 構成 | Medium tok/s | Long tok/s | Long acceptance |
|---|---|---:|---:|---:|
| FP16 | baseline | 115.2 | 116.0 | - |
| FP16 | MTP n=1 | 132.0 | 138.0 | 0.668 |
| FP16 | MTP n=3 | 121.3 | 145.1 | 0.498 |
| FP16 | MTP n=5 | 93.8 | 107.8 | 0.280 |
| FP8 | baseline | 123.8 | 124.4 | - |
| FP8 | **MTP n=1** | **149.2** | **155.6** | **0.684** |
| FP8 | MTP n=3 | 129.9 | 149.4 | 0.455 |
| FP8 | MTP n=5 | 99.4 | 111.8 | 0.268 |
| AWQ4 | baseline | 162.6 | 163.9 | - |
| AWQ4 | MTP n=1 | 181.0 | 181.8 | 0.681 |
| AWQ4 | MTP n=3 | 136.7 | 165.1 | 0.459 |
| AWQ4 | MTP n=5 | 110.8 | 130.9 | 0.313 |

英語では acceptance rate が全構成で上昇し、**n=3 も実用的な選択肢** になる。

### 4B D-Flash / MTP ─ 日本語 vs 英語

| 構成 | JA Medium | EN Medium | JA Long | EN Long |
|---|---:|---:|---:|---:|
| Base-FP8 | 59.8 | 59.9 | 60.0 | 60.1 |
| DFlash n=15 | 62.8 (+5%) | **80.4 (+34%)** | 71.0 (+18%) | **94.1 (+57%)** |
| MTP n=3 | 70.3 (+18%) | 77.8 (+30%) | 70.6 (+18%) | 84.0 (+40%) |

日本語では MTP n=3 と D-Flash がほぼ同速。英語では D-Flash が MTP を上回る。  
baseline の tok/s は日英で変わらない (言語は推論速度に影響しない)。

### Ollama 参考値 (2B Q8_0)

| workload | JA eval tok/s | EN eval tok/s |
|---|---:|---:|
| Medium | 155.9 | 158.4 |
| Long | 155.9 | 158.1 |

vLLM とは API・tokenization が異なるため、直接比較には使わない。

## 注意点

- このリポジトリの結果は RTX 4070 12GB 前提です
- 4B は `--enforce-eager` 前提です。CUDA graph を有効にするとこの環境では OOM になります
- `gpu-memory-utilization` は 0.937 が実質上限。0.94 以上は起動時に OOM になります
- `surogate/Qwen3.5-2B-FP8` は MTP acceptance rate = 0% のため使用禁止
- `lovedheart/Qwen3.5-4B-FP8` は 4B には使用禁止 (humming 量子化 + VL 系で起動不安定)
- Ollama の値は vLLM との厳密比較ではなく参考値です
