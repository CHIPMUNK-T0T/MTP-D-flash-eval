# Phase 2 Load Benchmark Summary

Warmup batches are excluded. Each measured batch sends concurrent OpenAI-compatible chat requests.

| config | framework | backend | case | conc | prompt tokens | status | success | fail | median aggregate tok/s | p95 request ms | median batch ms | peak VRAM MB |
|---|---|---|---|---:|---:|---|---:|---:|---:|---:|---:|---:|
| vllm_flash_attn | vllm | flash_attn | c1_limit_8k | 1 | 7395 | ok | 5 | 0 | 52.57 | 9741.0 | 9739.0 | 10215 |
| vllm_flash_attn | vllm | flash_attn | c2_limit_8k_each | 2 | 7395 | ok | 10 | 0 | 90.01 | 11377.0 | 11377.0 | 10215 |
| vllm_flash_attn | vllm | flash_attn | c4_4k_each | 4 | 4323 | ok | 20 | 0 | 170.00 | 12046.0 | 12047.0 | 10215 |
| vllm_flash_attn | vllm | flash_attn | c8_2k_each | 8 | 2189 | ok | 40 | 0 | 277.36 | 7385.0 | 7384.0 | 10255 |
| vllm_flashinfer | vllm | flashinfer | c1_limit_8k | 1 | 7395 | ok | 5 | 0 | 52.73 | 9710.0 | 9710.0 | 10595 |
| vllm_flashinfer | vllm | flashinfer | c2_limit_8k_each | 2 | 7395 | ok | 10 | 0 | 90.25 | 11346.0 | 11346.0 | 10615 |
| vllm_flashinfer | vllm | flashinfer | c4_4k_each | 4 | 4323 | ok | 20 | 0 | 170.54 | 12010.0 | 12009.0 | 10615 |
| vllm_flashinfer | vllm | flashinfer | c8_2k_each | 8 | 2189 | ok | 40 | 0 | 278.45 | 7355.0 | 7355.0 | 10655 |
| vllm_triton_attn | vllm | triton_attn | c1_limit_8k | 1 | 7395 | ok | 5 | 0 | 52.44 | 9766.0 | 9764.0 | 10215 |
| vllm_triton_attn | vllm | triton_attn | c2_limit_8k_each | 2 | 7395 | ok | 10 | 0 | 89.24 | 11477.0 | 11475.0 | 10215 |
| vllm_triton_attn | vllm | triton_attn | c4_4k_each | 4 | 4323 | ok | 20 | 0 | 169.30 | 12098.0 | 12097.0 | 10235 |
| vllm_triton_attn | vllm | triton_attn | c8_2k_each | 8 | 2189 | ok | 40 | 0 | 276.46 | 7411.0 | 7408.0 | 10255 |
| sglang_flashinfer | sglang | flashinfer | c1_limit_8k | 1 | 7395 | ok | 5 | 0 | 67.43 | 7597.0 | 7593.0 | 11285 |
| sglang_flashinfer | sglang | flashinfer | c2_limit_8k_each | 2 | 7395 | ok | 10 | 0 | 127.63 | 8028.0 | 8023.0 | 11285 |
| sglang_flashinfer | sglang | flashinfer | c4_4k_each | 4 | 4323 | ok | 20 | 0 | 253.59 | 8077.0 | 8076.0 | 11285 |
| sglang_flashinfer | sglang | flashinfer | c8_2k_each | 8 | 2189 | ok | 40 | 0 | 468.01 | 4375.0 | 4376.0 | 11285 |
| sglang_triton | sglang | triton | c1_limit_8k | 1 | 7395 | ok | 5 | 0 | 66.74 | 7674.0 | 7672.0 | 10821 |
| sglang_triton | sglang | triton | c2_limit_8k_each | 2 | 7395 | ok | 10 | 0 | 126.31 | 8116.0 | 8107.0 | 10821 |
| sglang_triton | sglang | triton | c4_4k_each | 4 | 4323 | ok | 20 | 0 | 251.23 | 8157.0 | 8152.0 | 10821 |
| sglang_triton | sglang | triton | c8_2k_each | 8 | 2189 | ok | 40 | 0 | 466.83 | 4387.0 | 4387.0 | 10821 |
