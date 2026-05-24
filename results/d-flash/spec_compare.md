# Qwen3.5-4B Speculative Decoding Compare

Common settings: FP8 target, `--enforce-eager`, max-num-batched-tokens 4096, max model len 2048, concurrency 1, warmup 1 + measured 5.

## medium

| Config | Method | n | tok/s median | Speedup vs baseline | Speedup vs D-Flash | Acceptance | Status |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Base-FP8 FP8 baseline | none | 0 | 59.80 | 1.00 | 0.95 | - | ok |
| DFlash-FP8-n15 FP8 D-Flash n=15 | dflash | 15 | 62.79 | 1.05 | 1.00 | 0.0400 | ok |
| MTP-FP8-n3 FP8 MTP n=3 | mtp | 3 | 70.33 | 1.18 | 1.12 | 0.3307 | ok |

## long

| Config | Method | n | tok/s median | Speedup vs baseline | Speedup vs D-Flash | Acceptance | Status |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Base-FP8 FP8 baseline | none | 0 | 59.97 | 1.00 | 0.84 | - | ok |
| DFlash-FP8-n15 FP8 D-Flash n=15 | dflash | 15 | 70.98 | 1.18 | 1.00 | 0.0535 | ok |
| MTP-FP8-n3 FP8 MTP n=3 | mtp | 3 | 70.59 | 1.18 | 0.99 | 0.3333 | ok |

