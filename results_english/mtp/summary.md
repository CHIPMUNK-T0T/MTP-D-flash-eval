# MTP Benchmark Summary

## medium

| Config | Quant | MTP | n | Batched | tok/s median | Speedup vs Base-FP16 | Acceptance | Notes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Base-FP16 | fp16 | no | 0 | 4096 | 115.16 | 1.00 | - |  |
| MTP-FP16-n1 | fp16 | yes | 1 | 4096 | 131.96 | 1.15 | 0.5938 |  |
| MTP-FP16-n3 | fp16 | yes | 3 | 4096 | 121.33 | 1.05 | 0.3634 |  |
| MTP-FP16-n5 | fp16 | yes | 5 | 4096 | 93.81 | 0.81 | 0.2180 |  |
| Base-AWQ4 | awq4 | no | 0 | 4096 | 162.64 | 1.41 | - |  |
| MTP-AWQ4-n1 | awq4 | yes | 1 | 4096 | 181.05 | 1.57 | 0.6776 |  |
| MTP-AWQ4-n3 | awq4 | yes | 3 | 4096 | 136.68 | 1.19 | 0.3282 |  |
| MTP-AWQ4-n5 | awq4 | yes | 5 | 4096 | 110.77 | 0.96 | 0.2356 |  |
| Base-FP8 | fp8 | no | 0 | 4096 | 123.79 | 1.07 | - |  |
| MTP-FP8-n1 | fp8 | yes | 1 | 4096 | 149.18 | 1.30 | 0.6306 |  |
| MTP-FP8-n3 | fp8 | yes | 3 | 4096 | 129.88 | 1.13 | 0.3577 |  |
| MTP-FP8-n5 | fp8 | yes | 5 | 4096 | 99.42 | 0.86 | 0.2180 |  |

## long

| Config | Quant | MTP | n | Batched | tok/s median | Speedup vs Base-FP16 | Acceptance | Notes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Base-FP16 | fp16 | no | 0 | 4096 | 116.05 | 1.00 | - |  |
| MTP-FP16-n1 | fp16 | yes | 1 | 4096 | 138.01 | 1.19 | 0.6678 |  |
| MTP-FP16-n3 | fp16 | yes | 3 | 4096 | 145.12 | 1.25 | 0.4976 |  |
| MTP-FP16-n5 | fp16 | yes | 5 | 4096 | 107.77 | 0.93 | 0.2798 |  |
| Base-AWQ4 | awq4 | no | 0 | 4096 | 163.89 | 1.41 | - |  |
| MTP-AWQ4-n1 | awq4 | yes | 1 | 4096 | 181.75 | 1.57 | 0.6809 |  |
| MTP-AWQ4-n3 | awq4 | yes | 3 | 4096 | 165.05 | 1.42 | 0.4589 |  |
| MTP-AWQ4-n5 | awq4 | yes | 5 | 4096 | 130.91 | 1.13 | 0.3130 |  |
| Base-FP8 | fp8 | no | 0 | 4096 | 124.36 | 1.07 | - |  |
| MTP-FP8-n1 | fp8 | yes | 1 | 4096 | 155.58 | 1.34 | 0.6842 |  |
| MTP-FP8-n3 | fp8 | yes | 3 | 4096 | 149.36 | 1.29 | 0.4552 |  |
| MTP-FP8-n5 | fp8 | yes | 5 | 4096 | 111.81 | 0.96 | 0.2676 |  |

