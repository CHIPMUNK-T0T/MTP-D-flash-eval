# Benchmark Summary

Generated after `benchmark_all.sh` completes.

| Suite | Config | Workload | tok/s median | Acceptance | Status | Source |
| --- | --- | --- | ---: | ---: | --- | --- |
| 2b-mtp | Base-FP16 | medium | 115.3673 |  | ok | mtp/summary.csv |
| 2b-mtp | Base-FP16 | long | 115.9683 |  | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP16-n1 | medium | 126.4198 | 0.5179 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP16-n1 | long | 133.4724 | 0.6019 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP16-n3 | medium | 119.6821 | 0.3604 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP16-n3 | long | 120.5557 | 0.3563 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP16-n5 | medium | 94.2563 | 0.2231 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP16-n5 | long | 91.1194 | 0.2071 | ok | mtp/summary.csv |
| 2b-mtp | Base-AWQ4 | medium | 161.9228 |  | ok | mtp/summary.csv |
| 2b-mtp | Base-AWQ4 | long | 164.0500 |  | ok | mtp/summary.csv |
| 2b-mtp | MTP-AWQ4-n1 | medium | 180.2817 | 0.6776 | ok | mtp/summary.csv |
| 2b-mtp | MTP-AWQ4-n1 | long | 172.9146 | 0.6019 | ok | mtp/summary.csv |
| 2b-mtp | MTP-AWQ4-n3 | medium | 151.0324 | 0.3932 | ok | mtp/summary.csv |
| 2b-mtp | MTP-AWQ4-n3 | long | 140.5435 | 0.3399 | ok | mtp/summary.csv |
| 2b-mtp | MTP-AWQ4-n5 | medium | 116.7351 | 0.2554 | ok | mtp/summary.csv |
| 2b-mtp | MTP-AWQ4-n5 | long | 108.3598 | 0.2223 | ok | mtp/summary.csv |
| 2b-mtp | Base-FP8 | medium | 122.3125 |  | ok | mtp/summary.csv |
| 2b-mtp | Base-FP8 | long | 123.8810 |  | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP8-n1 | medium | 143.0967 | 0.5706 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP8-n1 | long | 147.3381 | 0.5969 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP8-n3 | medium | 112.6265 | 0.2611 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP8-n3 | long | 131.1140 | 0.3618 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP8-n5 | medium | 88.4895 | 0.1696 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP8-n5 | long | 100.1565 | 0.2221 | ok | mtp/summary.csv |
| 4b-dflash | Base-FP8 | medium | 59.7991 |  | ok | d-flash/summary.csv |
| 4b-dflash | Base-FP8 | long | 59.9672 |  | ok | d-flash/summary.csv |
| 4b-dflash | DFlash-FP8-n15 | medium | 62.7913 | 0.0400 | ok | d-flash/summary.csv |
| 4b-dflash | DFlash-FP8-n15 | long | 70.9829 | 0.0535 | ok | d-flash/summary.csv |
| 4b-mtp | MTP-FP8-n3 | medium | 70.3297 | 0.3307 | ok | d-flash/mtp_summary.csv |
| 4b-mtp | MTP-FP8-n3 | long | 70.5915 | 0.3333 | ok | d-flash/mtp_summary.csv |
| ollama | qwen35-2b-bench | medium | 155.9155 |  | ok | ollama/summary.csv |
| ollama | qwen35-2b-bench | long | 155.8933 |  | ok | ollama/summary.csv |
