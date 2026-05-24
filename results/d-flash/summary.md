# Qwen3.5-4B D-Flash Benchmark Summary

Common settings: FP8 target, `--enforce-eager`, max-num-batched-tokens 4096, max model len 2048, concurrency 1, warmup 1 + measured 5.

## medium

| Config | D-Flash | n | tok/s median | Speedup vs Base-FP8 | Acceptance | Status | Notes |
| --- | --- | ---: | ---: | ---: | ---: | --- | --- |
| Base-FP8 FP8 baseline | no | 0 | 59.80 | 1.00 | - | ok |  |
| DFlash-FP8-n15 FP8 D-Flash n=15 | yes | 15 | 62.79 | 1.05 | 0.0400 | ok |  |

## long

| Config | D-Flash | n | tok/s median | Speedup vs Base-FP8 | Acceptance | Status | Notes |
| --- | --- | ---: | ---: | ---: | ---: | --- | --- |
| Base-FP8 FP8 baseline | no | 0 | 59.97 | 1.00 | - | ok |  |
| DFlash-FP8-n15 FP8 D-Flash n=15 | yes | 15 | 70.98 | 1.18 | 0.0535 | ok |  |

