# Token Accounting Note

This failed `long_ctx8192` run is intentionally kept because it is useful for the article.

Observation:
- The same `ctx8192.txt` input and the same `max_tokens=512` request failed differently across runtimes.
- vLLM reported `prompt contains at least 7681 input tokens` and `7681 + 512 = 8193`, exceeding `max_model_len=8192` by 1 token.
- SGLang reported `The input (8284 tokens) is longer than the model's context length (8192 tokens)`.

Interpretation:
- This is not an attention backend performance issue.
- This is not an RTX 4070 OOM result.
- The likely cause is different chat template handling, internal prompt formatting, tokenizer path, or request conversion between vLLM and SGLang.
- Therefore the failed rows are useful evidence that identical user text can become a different token count depending on the serving runtime.

Action for the main benchmark:
- Keep `context_length=8192` and `max_tokens=512` unchanged.
- Shorten only `backend_compare/prompts/ctx8192.txt` so the main benchmark remains valid while preserving the runtime/token-accounting observation above.
