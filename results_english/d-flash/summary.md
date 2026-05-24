# Qwen3.5-4B D-Flash Benchmark Summary

Common settings: FP8 target, `--enforce-eager`, max-num-batched-tokens 4096, max model len 2048, concurrency 1, warmup 1 + measured 5.

## medium

| Config | D-Flash | n | tok/s median | Speedup vs Base-FP8 | Acceptance | Status | Notes |
| --- | --- | ---: | ---: | ---: | ---: | --- | --- |
| Base-FP8 FP8 baseline | no | 0 | 59.93 | 1.00 | - | ok |  |
| DFlash-FP8-n15 FP8 D-Flash n=15 | yes | 15 | 80.35 | 1.34 | 0.0704 | ok |  |

## long

| Config | D-Flash | n | tok/s median | Speedup vs Base-FP8 | Acceptance | Status | Notes |
| --- | --- | ---: | ---: | ---: | ---: | --- | --- |
| Base-FP8 FP8 baseline | no | 0 | 60.14 | 1.00 | - | ok |  |
| DFlash-FP8-n15 FP8 D-Flash n=15 | yes | 15 | 94.08 | 1.56 | 0.0951 | ok |  |

