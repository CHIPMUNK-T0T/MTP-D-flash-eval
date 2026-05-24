# Qwen3.5 vLLM Speculative Decoding Benchmark

Qwen3.5 のローカル推論で、MTP と D-Flash による速度変化を測ったリポジトリです。  
RTX 4070 12GB 上で動かすことを前提にしています。

主に次の2つを評価しています。

- Qwen3.5-2B の `qwen3_next_mtp`
- Qwen3.5-4B FP8 の D-Flash と MTP 比較

Qiita 記事用のドラフトは以下です。

- `Blog_draft.md`: Qwen3.5-2B MTP 評価
- `Blog_draft_dflash.md`: Qwen3.5-4B D-Flash 評価

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
    medium.txt
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

benchmark_mtp.sh
benchmark_dflash.sh
benchmark_ollama.sh
benchmark_all.sh

results/
  summary.csv
  summary.md
  mtp/
  d-flash/
  ollama/
  logs/
  metrics/

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

スクリプト名は `n=3` も明示しています。

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
bash benchmark_mtp.sh
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
VRAM に余裕がある環境では、FP8 ではなく BF16 target で同様の条件を試す起点にできます。

スクリプト:

```text
docker_vllm/dflash/qwen35-4b-fp8.sh
docker_vllm/dflash/qwen35-4b-fp8-dflash-n15.sh
docker_vllm/dflash/qwen35-4b-fp8-mtp-n3.sh
docker_vllm/dflash/qwen35-4b-fp16.sh
docker_vllm/dflash/qwen35-4b-fp16-dflash-n15.sh
```

`qwen35-4b-fp16.sh` と `qwen35-4b-fp16-dflash-n15.sh` は参考用です。  
この RTX 4070 12GB 環境では VRAM 不足で実測対象にしていません。

D-Flash baseline/D-Flash と MTP n=3 比較をまとめて計測:

```bash
bash benchmark_dflash.sh
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
bash benchmark_ollama.sh
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

出力:

```text
results/ollama/requests.csv
results/ollama/summary.csv
results/ollama/summary.md
results/ollama/responses/
```

## 全実行

2B MTP、4B D-Flash/MTP、Ollama 参考値を順に実行し、最後に統合サマリーを作ります。

```bash
bash benchmark_all.sh
```

統合サマリーは、全ベンチが完了した後に作成します。
既存結果からサマリーだけ作り直す場合は `bash benchmark_all.sh --summary-only` を使います。

```text
results/summary.csv
results/summary.md
```

## 結果概要

### 2B MTP

Medium は出力 256 tokens、Long は出力 512 tokens です。

| 量子化 | 構成 | Medium tok/s | Long tok/s |
|---|---|---:|---:|
| FP16 | baseline | 88.86 | 88.69 |
| FP16 | MTP n=1 | 118.52 | 121.82 |
| FP16 | MTP n=3 | 137.19 | 141.05 |
| FP16 | MTP n=5 | 124.70 | 140.62 |
| FP8 | baseline | 109.40 | 108.45 |
| FP8 | MTP n=1 | 169.87 | 168.59 |
| FP8 | MTP n=3 | 161.01 | 195.64 |
| FP8 | MTP n=5 | 160.80 | 183.91 |
| AWQ4 | baseline | 159.90 | 151.66 |
| AWQ4 | MTP n=1 | 203.50 | 215.58 |
| AWQ4 | MTP n=3 | 209.15 | 265.84 |
| AWQ4 | MTP n=5 | 175.34 | 285.24 |

2B では MTP により全体的に速度が上がりました。  
FP16 / FP8 では n=3 が扱いやすく、FP8 Long では baseline 比 1.80倍でした。

AWQ4 は速度だけ見ると強いですが、Long 条件で baseline/MTP ともに出力ループが出たため、品質 caveat 付きです。

### 4B D-Flash / MTP

| 構成 | Method | n | Medium tok/s | Long tok/s |
|---|---|---:|---:|---:|
| baseline | none | 0 | 60.22 | 60.48 |
| D-Flash | dflash | 15 | 144.47 | 156.81 |
| MTP | qwen3_next_mtp | 3 | 94.12 | 75.80 |

4B FP8 では D-Flash が最も速くなりました。

| 構成 | Medium speedup | Long speedup |
|---|---:|---:|
| D-Flash n=15 | 2.40x | 2.59x |
| MTP n=3 | 1.56x | 1.25x |

MTP n=3 も baseline より速いですが、今回の RTX 4070 12GB / eager mode 条件では D-Flash n=15 が明確に上でした。

acceptance rate は MTP の方が高いですが、実速度は D-Flash の方が高くなりました。

| 構成 | Medium acceptance | Long acceptance |
|---|---:|---:|
| D-Flash n=15 | 0.1833 | 0.2037 |
| MTP n=3 | 0.5649 | 0.3794 |

## 注意点

- このリポジトリの結果は RTX 4070 12GB 前提です。
- 4B は `--enforce-eager` 前提です。
- 4B で CUDA graph を有効にすると、この環境では OOM になりました。
- AWQ4 Long の速度値は品質 caveat 付きです。
- Ollama の値は vLLM との厳密比較ではなく参考値です。
