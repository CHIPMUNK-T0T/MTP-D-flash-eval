# Backend Benchmark Summary

warmup runs are excluded from measured medians.

| config | framework | backend | workload | prompt tokens | status | median tok/s | median elapsed ms | notes |
|---|---|---|---|---:|---|---:|---:|---|
| vllm_flash_attn | vllm | flash_attn | long_ctx8192 | 7395 | ok | 52.51 | 9751.0 |  |
| vllm_flashinfer | vllm | flashinfer | long_ctx8192 | 7395 | ok | 52.64 | 9727.0 |  |
| vllm_triton_attn | vllm | triton_attn | long_ctx8192 | 7395 | ok | 52.34 | 9782.0 |  |
| sglang_flashinfer | sglang | flashinfer | long_ctx8192 | 7395 | ok | 67.47 | 7589.0 |  |
| sglang_triton | sglang | triton | long_ctx8192 | 7395 | ok | 66.92 | 7651.0 |  |
