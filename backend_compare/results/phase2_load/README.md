# Phase 2 Load Results

This directory is reserved for the Phase 2 load benchmark.

The benchmark keeps Phase 1 results untouched and records all concurrent-load
results here:

- `summary.csv`: one row per backend and load case
- `summary.md`: readable summary table
- `requests.csv`: one row per measured request
- `logs/`: container startup/final logs and per-case GPU samples
- `responses/`: raw JSON, text outputs, and request errors

Default matrix:

- vLLM: `flash_attn`, `flashinfer`, `triton_attn`
- SGLang: `flashinfer`, `triton`
- concurrency/load cases: `1`, `2`, `4`, `8`

Each concurrency level uses a different per-request prompt length so the active
token budget stays near the 8192 context limit while stressing parallel serving.
The summary also records peak VRAM and peak GPU utilization sampled during each case.
