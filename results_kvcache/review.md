# Qwen3.5-4B KV Cache Result Review

## Runtime/API status

- base_fa_ctx_8k: status=ctx_too_long, notes=
- base_fa_ctx_32k: status=ctx_too_long, notes=
- base_fi_ctx_8k: status=ctx_too_long, notes=
- base_fi_ctx_32k: status=ctx_too_long, notes=
- base_fi_8k_ctx_32k: status=ctx_too_long, notes=
- base_fi_96k_medium: status=model_limit, notes=model_limit
- base_fi_96k_long: status=model_limit, notes=model_limit
- base_fi_96k_ctx_long: status=model_limit, notes=model_limit
- base_fi_96k_ctx_8k: status=model_limit, notes=model_limit
- base_fi_96k_ctx_32k: status=model_limit, notes=model_limit
- fp8kv_2k_ctx_8k: status=ctx_too_long, notes=
- fp8kv_2k_ctx_32k: status=ctx_too_long, notes=
- fp8kv_8k_ctx_32k: status=ctx_too_long, notes=

## Quality scan

- No obvious repetition loops detected.
