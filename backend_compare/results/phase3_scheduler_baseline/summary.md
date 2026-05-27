# Phase 3 Scheduler Benchmark Summary

目的: Phase 2で見えた並列負荷時の差を、streaming計測でTTFT・ITL・混在負荷・scheduler tuningに分解する。

Warmup batches are excluded. Streaming responses are used, so TTFT and ITL are measured from received chunks.

| config | case | purpose | conc | status | agg tok/s | p95 TTFT ms | p95 ITL ms | p95 req ms | peak VRAM MB |
|---|---|---|---:|---|---:|---:|---:|---:|---:|
| vllm_flashinfer_base | hom_c8_2k_each | Phase2 c8 throughputをTTFTとITLに分解する | 8 | ok | 277.66 | 2295.14 | 20.40 | 7363.00 | 10655 |
| vllm_flashinfer_base | mix_short6_long2_c8 | 長いprefillが短い依頼のTTFT/p95を悪化させるかを見る | 8 | ok | 344.44 | 1020.83 | 19.78 | 5920.00 | 10655 |
| vllm_flashinfer_base | prefill_heavy_c4_4k_each | 入力処理が重い時のscheduler/prefill処理を見る | 4 | ok | 109.12 | 2291.75 | 19.35 | 4692.00 | 10655 |
| vllm_flashinfer_base | decode_heavy_c8_short | 出力生成が長い時のITLとdecode安定性を見る | 8 | ok | 401.04 | 636.74 | 19.81 | 20326.00 | 10655 |
| sglang_flashinfer_base | hom_c8_2k_each | Phase2 c8 throughputをTTFTとITLに分解する | 8 | ok | 465.35 | 277.64 | 17.04 | 4512.00 | 11285 |
| sglang_flashinfer_base | mix_short6_long2_c8 | 長いprefillが短い依頼のTTFT/p95を悪化させるかを見る | 8 | ok | 465.24 | 332.55 | 16.87 | 4512.00 | 11285 |
| sglang_flashinfer_base | prefill_heavy_c4_4k_each | 入力処理が重い時のscheduler/prefill処理を見る | 4 | ok | 240.47 | 249.21 | 15.92 | 2232.00 | 11285 |
| sglang_flashinfer_base | decode_heavy_c8_short | 出力生成が長い時のITLとdecode安定性を見る | 8 | ok | 478.62 | 249.40 | 16.95 | 17098.00 | 11285 |
