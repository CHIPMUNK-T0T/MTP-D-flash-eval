# MTP Benchmark Summary

## medium

| Config | Quant | MTP | n | Batched | tok/s median | Speedup vs Base-FP16 | Acceptance | Notes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Base-FP16 | fp16 | no | 0 | 4096 | 115.37 | 1.00 | - |  |
| MTP-FP16-n1 | fp16 | yes | 1 | 4096 | 126.42 | 1.10 | 0.5179 |  |
| MTP-FP16-n3 | fp16 | yes | 3 | 4096 | 119.68 | 1.04 | 0.3604 |  |
| MTP-FP16-n5 | fp16 | yes | 5 | 4096 | 94.26 | 0.82 | 0.2231 |  |
| Base-AWQ4 | awq4 | no | 0 | 4096 | 161.92 | 1.40 | - |  |
| MTP-AWQ4-n1 | awq4 | yes | 1 | 4096 | 180.28 | 1.56 | 0.6776 |  |
| MTP-AWQ4-n3 | awq4 | yes | 3 | 4096 | 151.03 | 1.31 | 0.3932 |  |
| MTP-AWQ4-n5 | awq4 | yes | 5 | 4096 | 116.74 | 1.01 | 0.2554 |  |
| Base-FP8 | fp8 | no | 0 | 4096 | 122.31 | 1.06 | - |  |
| MTP-FP8-n1 | fp8 | yes | 1 | 4096 | 143.10 | 1.24 | 0.5706 |  |
| MTP-FP8-n3 | fp8 | yes | 3 | 4096 | 112.63 | 0.98 | 0.2611 |  |
| MTP-FP8-n5 | fp8 | yes | 5 | 4096 | 88.49 | 0.77 | 0.1696 |  |

## long

| Config | Quant | MTP | n | Batched | tok/s median | Speedup vs Base-FP16 | Acceptance | Notes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| Base-FP16 | fp16 | no | 0 | 4096 | 115.97 | 1.00 | - |  |
| MTP-FP16-n1 | fp16 | yes | 1 | 4096 | 133.47 | 1.15 | 0.6019 |  |
| MTP-FP16-n3 | fp16 | yes | 3 | 4096 | 120.56 | 1.04 | 0.3563 |  |
| MTP-FP16-n5 | fp16 | yes | 5 | 4096 | 91.12 | 0.79 | 0.2071 |  |
| Base-AWQ4 | awq4 | no | 0 | 4096 | 164.05 | 1.41 | - |  |
| MTP-AWQ4-n1 | awq4 | yes | 1 | 4096 | 172.91 | 1.49 | 0.6019 |  |
| MTP-AWQ4-n3 | awq4 | yes | 3 | 4096 | 140.54 | 1.21 | 0.3399 |  |
| MTP-AWQ4-n5 | awq4 | yes | 5 | 4096 | 108.36 | 0.93 | 0.2223 |  |
| Base-FP8 | fp8 | no | 0 | 4096 | 123.88 | 1.07 | - |  |
| MTP-FP8-n1 | fp8 | yes | 1 | 4096 | 147.34 | 1.27 | 0.5969 |  |
| MTP-FP8-n3 | fp8 | yes | 3 | 4096 | 131.11 | 1.13 | 0.3618 |  |
| MTP-FP8-n5 | fp8 | yes | 5 | 4096 | 100.16 | 0.86 | 0.2221 |  |

