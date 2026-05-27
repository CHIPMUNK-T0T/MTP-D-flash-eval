# Backend Benchmark Summary

warmup runs are excluded from measured medians.

| config | framework | backend | workload | prompt tokens | status | median tok/s | median elapsed ms | notes |
|---|---|---|---|---:|---|---:|---:|---|
| vllm_flash_attn | vllm | flash_attn | short_ctx512 | 538 | ok | 59.47 | 4305.0 |  |
| vllm_flash_attn | vllm | flash_attn | mid_ctx2048 | 2135 | ok | 58.11 | 8811.0 |  |
| vllm_flash_attn | vllm | flash_attn | long_ctx8192 |  | request_failed |  |  | see responses/vllm_flash_attn_long_ctx8192 |
| vllm_flashinfer | vllm | flashinfer | short_ctx512 | 538 | ok | 59.51 | 4302.0 |  |
| vllm_flashinfer | vllm | flashinfer | mid_ctx2048 | 2135 | ok | 58.13 | 8808.0 |  |
| vllm_flashinfer | vllm | flashinfer | long_ctx8192 |  | request_failed |  |  | see responses/vllm_flashinfer_long_ctx8192 |
| vllm_triton_attn | vllm | triton_attn | short_ctx512 | 538 | ok | 59.62 | 4294.0 |  |
| vllm_triton_attn | vllm | triton_attn | mid_ctx2048 | 2135 | ok | 58.26 | 8788.0 |  |
| vllm_triton_attn | vllm | triton_attn | long_ctx8192 |  | request_failed |  |  | see responses/vllm_triton_attn_long_ctx8192 |
| sglang_flashinfer | sglang | flashinfer | short_ctx512 | 538 | ok | 70.27 | 3643.0 |  |
| sglang_flashinfer | sglang | flashinfer | mid_ctx2048 | 2135 | ok | 70.47 | 7266.0 |  |
| sglang_flashinfer | sglang | flashinfer | long_ctx8192 |  | request_failed |  |  | see responses/sglang_flashinfer_long_ctx8192 |
| sglang_triton | sglang | triton | short_ctx512 | 538 | ok | 70.52 | 3630.0 |  |
| sglang_triton | sglang | triton | mid_ctx2048 | 2135 | ok | 70.60 | 7252.0 |  |
| sglang_triton | sglang | triton | long_ctx8192 |  | request_failed |  |  | see responses/sglang_triton_long_ctx8192 |
## Token Accounting Observation

The `long_ctx8192` failures are kept intentionally. They show that the same input text is counted differently by vLLM and SGLang: vLLM reported 7681 input tokens plus 512 output tokens, while SGLang reported 8284 input tokens. This is a runtime/token-accounting difference, not an attention backend speed result and not OOM. See `token_accounting_note.md`.

