# Phase 3 Scheduler Benchmark Summary

目的: Phase 2で見えた並列負荷時の差を、streaming計測でTTFT・ITL・混在負荷・scheduler tuningに分解する。

Warmup batches are excluded. Streaming responses are used, so TTFT and ITL are measured from received chunks.

| config | case | purpose | conc | status | agg tok/s | p95 TTFT ms | p95 ITL ms | p95 req ms | peak VRAM MB |
|---|---|---|---:|---|---:|---:|---:|---:|---:|
| vllm_flashinfer_seq8 | hom_c8_2k_each | Phase2 c8 throughputをTTFTとITLに分解する | 8 | ok | 278.31 | 2282.77 | 20.38 | 7361.00 | 10615 |
| vllm_flashinfer_seq8 | mix_short6_long2_c8 | 長いprefillが短い依頼のTTFT/p95を悪化させるかを見る | 8 | ok | 344.99 | 1024.03 | 19.78 | 5924.00 | 10615 |
| vllm_flashinfer_seq8 | prefill_heavy_c4_4k_each | 入力処理が重い時のscheduler/prefill処理を見る | 4 | ok | 109.02 | 2286.23 | 19.36 | 4701.00 | 10615 |
| vllm_flashinfer_seq8 | decode_heavy_c8_short | 出力生成が長い時のITLとdecode安定性を見る | 8 | ok | 400.63 | 642.82 | 19.78 | 20346.00 | 10615 |
| vllm_flashinfer_batch8192 | hom_c8_2k_each | Phase2 c8 throughputをTTFTとITLに分解する | 8 | ok | 277.67 | 2332.51 | 20.48 | 7401.00 | 11217 |
| vllm_flashinfer_batch8192 | mix_short6_long2_c8 | 長いprefillが短い依頼のTTFT/p95を悪化させるかを見る | 8 | ok | 343.37 | 1066.49 | 19.82 | 5968.00 | 11217 |
| vllm_flashinfer_batch8192 | prefill_heavy_c4_4k_each | 入力処理が重い時のscheduler/prefill処理を見る | 4 | ok | 108.75 | 2309.78 | 19.30 | 4710.00 | 11217 |
| vllm_flashinfer_batch8192 | decode_heavy_c8_short | 出力生成が長い時のITLとdecode安定性を見る | 8 | ok | 400.75 | 636.17 | 19.78 | 20330.00 | 11217 |
| sglang_flashinfer_run8 | hom_c8_2k_each | Phase2 c8 throughputをTTFTとITLに分解する | 8 | ok | 464.29 | 164.19 | 17.04 | 4406.00 | 11285 |
| sglang_flashinfer_run8 | mix_short6_long2_c8 | 長いprefillが短い依頼のTTFT/p95を悪化させるかを見る | 8 | ok | 473.20 | 250.32 | 16.86 | 4431.00 | 11289 |
| sglang_flashinfer_run8 | prefill_heavy_c4_4k_each | 入力処理が重い時のscheduler/prefill処理を見る | 4 | ok | 241.62 | 253.75 | 15.92 | 2234.00 | 11289 |
| sglang_flashinfer_run8 | decode_heavy_c8_short | 出力生成が長い時のITLとdecode安定性を見る | 8 | ok | 481.67 | 174.44 | 16.94 | 17023.00 | 11289 |
| sglang_flashinfer_chunk4096 | hom_c8_2k_each | Phase2 c8 throughputをTTFTとITLに分解する | 8 | ok | 450.51 | 397.38 | 17.04 | 4630.00 | 11629 |
| sglang_flashinfer_chunk4096 | mix_short6_long2_c8 | 長いprefillが短い依頼のTTFT/p95を悪化させるかを見る | 8 | ok | 442.72 | 448.45 | 16.80 | 4625.00 | 11629 |
| sglang_flashinfer_chunk4096 | prefill_heavy_c4_4k_each | 入力処理が重い時のscheduler/prefill処理を見る | 4 | ok | 217.78 | 478.29 | 15.84 | 2451.00 | 11661 |
| sglang_flashinfer_chunk4096 | decode_heavy_c8_short | 出力生成が長い時のITLとdecode安定性を見る | 8 | ok | 471.56 | 502.91 | 16.95 | 17361.00 | 11661 |
