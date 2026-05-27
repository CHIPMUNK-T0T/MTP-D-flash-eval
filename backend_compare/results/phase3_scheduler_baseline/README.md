# Phase 3 Scheduler / Streaming Latency

Phase 3は、Phase 2で見えた「並列時にSGLangが強い」という結果を、schedulerとbatchingの観点で分解するための実験です。

見るもの:
- TTFT: prefill待ち、queue待ち、chunked prefillの効き方
- ITL: decode中の安定性、token間隔のばらつき
- mixed workload: 長い入力が短い依頼を巻き込んで遅くするか
- tuning: 同時実行数やbatched token上限を変えると、throughputとp95 latencyがどう変わるか

デフォルト:
- `CONFIG_SET=baseline`: vLLM flashinfer と SGLang flashinfer
- `CASE_SET=core`: c8同質負荷、short/long混在、prefill重視、decode重視

拡張:
- `CASE_SET=latency_scale`: c1/c2/c4/c8の同質負荷でスケールを見る
- `CONFIG_SET=tuning`: scheduler系パラメータだけを見る
- `CONFIG_SET=all CASE_SET=all`: 全部回す

実行例:
- `bash backend_compare/run_phase3_scheduler.sh --dry-run`
- `CASE_SET=core CONFIG_SET=baseline bash backend_compare/run_phase3_scheduler.sh`
- `CASE_FILTER=mix_short6_long2_c8 CONFIG_SET=tuning bash backend_compare/run_phase3_scheduler.sh`

出力:
- `summary.csv`: config x caseの集約結果
- `requests.csv`: request単位のTTFT/ITL/elapsed
- `summary.md`: 記事用に読みやすい集約
- `responses/`: streaming eventと生成テキスト
- `logs/`: startup logとGPU samples

注: streamingレスポンスでusageが返らない場合、tok/sは受信したcontent chunk数ベースの近似になります。TTFT/ITLはそのまま比較できます。
