# Phase1 Overflow Reference

reference failures from the original long_ctx8192 overflow run. total rows: 5.

| config | framework | backend | workload | status | notes |
|---|---|---|---|---|---|
| sglang_flashinfer | sglang | flashinfer | long_ctx8192 | request_failed | see responses/sglang_flashinfer_long_ctx8192 |
| sglang_triton | sglang | triton | long_ctx8192 | request_failed | see responses/sglang_triton_long_ctx8192 |
| vllm_flash_attn | vllm | flash_attn | long_ctx8192 | request_failed | see responses/vllm_flash_attn_long_ctx8192 |
| vllm_flashinfer | vllm | flashinfer | long_ctx8192 | request_failed | see responses/vllm_flashinfer_long_ctx8192 |
| vllm_triton_attn | vllm | triton_attn | long_ctx8192 | request_failed | see responses/vllm_triton_attn_long_ctx8192 |
