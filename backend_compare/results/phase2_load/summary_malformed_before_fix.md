# Phase 2 Load Benchmark Summary

Warmup batches are excluded. Each measured batch sends concurrent OpenAI-compatible chat requests.

| config | framework | backend | case | conc | prompt tokens | status | success | fail | median aggregate tok/s | p95 request ms | median batch ms | peak VRAM MB |
|---|---|---|---|---:|---:|---|---:|---:|---:|---:|---:|---:|
| vllm_flash_attn | vllm | flash_attn | c1_limit_8k | 1 | 7395 | ok | 5 | 0 | 52.57 | 9741.0 | 9739.0 | 10215 |
| vllm_flash_attn | vllm | flash_attn | c2_4k_each | 2 | 7395 |  | 10 | 10 | 11377.00 | 11377.0 | 0.0 | 45.06452666934431 |
| vllm_flash_attn | vllm | flash_attn | c4_2k_each | 4 | 4323 |  | 20 | 20 | 12046.00 | 12047.0 | 0.0 | 42.599218199877114 |
| vllm_flash_attn | vllm | flash_attn | c8_1k_each | 8 | 2189 |  | 40 | 40 | 7385.00 | 7384.0 | 0.0 | 34.79442761566803 |
| vllm_flashinfer | vllm | flashinfer | c1_limit_8k | 1 | 7395 | ok | 5 | 0 | 52.73 | 9710.0 | 9710.0 | 10595 |
| vllm_flashinfer | vllm | flashinfer | c2_4k_each | 2 | 7395 |  | 10 | 10 | 11346.00 | 11346.0 | 0.0 | 45.18982118784052 |
| vllm_flashinfer | vllm | flashinfer | c4_2k_each | 4 | 4323 |  | 20 | 20 | 12010.00 | 12009.0 | 0.0 | 42.69691216726332 |
| vllm_flashinfer | vllm | flashinfer | c8_1k_each | 8 | 2189 |  | 40 | 40 | 7355.00 | 7355.0 | 0.0 | 34.95596384150757 |
| vllm_triton_attn | vllm | triton_attn | c1_limit_8k | 1 | 7395 | ok | 5 | 0 | 52.44 | 9766.0 | 9764.0 | 10215 |
| vllm_triton_attn | vllm | triton_attn | c2_4k_each | 2 | 7395 |  | 10 | 10 | 11477.00 | 11475.0 | 0.0 | 44.679132215709274 |
| vllm_triton_attn | vllm | triton_attn | c4_2k_each | 4 | 4323 |  | 20 | 20 | 12098.00 | 12097.0 | 0.0 | 42.39815932728174 |
| vllm_triton_attn | vllm | triton_attn | c8_1k_each | 8 | 2189 |  | 40 | 40 | 7411.00 | 7408.0 | 0.0 | 34.68364720227611 |
| sglang_flashinfer | sglang | flashinfer | c1_limit_8k | 1 | 7395 | ok | 5 | 0 | 67.43 | 7597.0 | 7593.0 | 11285 |
| sglang_flashinfer | sglang | flashinfer | c2_4k_each | 2 | 7395 | 16 | 10 | 10 | 8028.00 | 8023.0 | 0.0 | 63.82448267265021 |
| sglang_flashinfer | sglang | flashinfer | c4_2k_each | 4 | 4323 | 16 | 20 | 20 | 8077.00 | 8076.0 | 0.0 | 63.405572755417964 |
| sglang_flashinfer | sglang | flashinfer | c8_1k_each | 8 | 2189 | 16 | 40 | 40 | 4375.00 | 4376.0 | 0.0 | 58.5544373284538 |
| sglang_triton | sglang | triton | c1_limit_8k | 1 | 7395 | ok | 5 | 0 | 66.74 | 7674.0 | 7672.0 | 10821 |
| sglang_triton | sglang | triton | c2_4k_each | 2 | 7395 | 16 | 10 | 10 | 8116.00 | 8107.0 | 0.0 | 63.16308906982482 |
| sglang_triton | sglang | triton | c4_2k_each | 4 | 4323 | 16 | 20 | 20 | 8157.00 | 8152.0 | 0.0 | 62.82208588957055 |
| sglang_triton | sglang | triton | c8_1k_each | 8 | 2189 | 16 | 40 | 40 | 4387.00 | 4387.0 | 0.0 | 58.434147454918964 |
