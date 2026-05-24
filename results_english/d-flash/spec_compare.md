# Qwen3.5-4B Speculative Decoding Compare

Common settings: FP8 target, `--enforce-eager`, max-num-batched-tokens 4096, max model len 2048, concurrency 1, warmup 1 + measured 5.

## medium

| Config | Method | n | tok/s median | Speedup vs baseline | Speedup vs D-Flash | Acceptance | Status |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Base-FP8 FP8 baseline | none | 0 | 59.93 | 1.00 | 0.75 | - | ok |
| DFlash-FP8-n15 FP8 D-Flash n=15 | dflash | 15 | 80.35 | 1.34 | 1.00 | 0.0704 | ok |
| MTP-FP8-n3 FP8 MTP n=3 | mtp | 3 | 77.76 | 1.30 | 0.97 | 0.4087 | ok |

## long

| Config | Method | n | tok/s median | Speedup vs baseline | Speedup vs D-Flash | Acceptance | Status |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Base-FP8 FP8 baseline | none | 0 | 60.14 | 1.00 | 0.64 | - | ok |
| DFlash-FP8-n15 FP8 D-Flash n=15 | dflash | 15 | 94.08 | 1.56 | 1.00 | 0.0951 | ok |
| MTP-FP8-n3 FP8 MTP n=3 | mtp | 3 | 83.95 | 1.40 | 0.89 | 0.4642 | ok |

