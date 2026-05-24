# Benchmark Summary (English prompts)

Generated after `benchmark_all_english.sh` completes.

| Suite | Config | Workload | tok/s median | Acceptance | Status | Source |
| --- | --- | --- | ---: | ---: | --- | --- |
| 2b-mtp | Base-FP16 | medium | 115.1597 |  | ok | mtp/summary.csv |
| 2b-mtp | Base-FP16 | long | 116.0471 |  | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP16-n1 | medium | 131.9588 | 0.5938 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP16-n1 | long | 138.0054 | 0.6678 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP16-n3 | medium | 121.3270 | 0.3634 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP16-n3 | long | 145.1247 | 0.4976 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP16-n5 | medium | 93.8073 | 0.2180 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP16-n5 | long | 107.7668 | 0.2798 | ok | mtp/summary.csv |
| 2b-mtp | Base-AWQ4 | medium | 162.6429 |  | ok | mtp/summary.csv |
| 2b-mtp | Base-AWQ4 | long | 163.8924 |  | ok | mtp/summary.csv |
| 2b-mtp | MTP-AWQ4-n1 | medium | 181.0467 | 0.6776 | ok | mtp/summary.csv |
| 2b-mtp | MTP-AWQ4-n1 | long | 181.7536 | 0.6809 | ok | mtp/summary.csv |
| 2b-mtp | MTP-AWQ4-n3 | medium | 136.6791 | 0.3282 | ok | mtp/summary.csv |
| 2b-mtp | MTP-AWQ4-n3 | long | 165.0548 | 0.4589 | ok | mtp/summary.csv |
| 2b-mtp | MTP-AWQ4-n5 | medium | 110.7746 | 0.2356 | ok | mtp/summary.csv |
| 2b-mtp | MTP-AWQ4-n5 | long | 130.9128 | 0.3130 | ok | mtp/summary.csv |
| 2b-mtp | Base-FP8 | medium | 123.7911 |  | ok | mtp/summary.csv |
| 2b-mtp | Base-FP8 | long | 124.3624 |  | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP8-n1 | medium | 149.1841 | 0.6306 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP8-n1 | long | 155.5758 | 0.6842 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP8-n3 | medium | 129.8833 | 0.3577 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP8-n3 | long | 149.3582 | 0.4552 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP8-n5 | medium | 99.4175 | 0.2180 | ok | mtp/summary.csv |
| 2b-mtp | MTP-FP8-n5 | long | 111.8148 | 0.2676 | ok | mtp/summary.csv |
| 4b-dflash | Base-FP8 | medium | 59.9251 |  | ok | d-flash/summary.csv |
| 4b-dflash | Base-FP8 | long | 60.1433 |  | ok | d-flash/summary.csv |
| 4b-dflash | DFlash-FP8-n15 | medium | 80.3515 | 0.0704 | ok | d-flash/summary.csv |
| 4b-dflash | DFlash-FP8-n15 | long | 94.0831 | 0.0951 | ok | d-flash/summary.csv |
| 4b-mtp | MTP-FP8-n3 | medium | 77.7643 | 0.4087 | ok | d-flash/mtp_summary.csv |
| 4b-mtp | MTP-FP8-n3 | long | 83.9482 | 0.4642 | ok | d-flash/mtp_summary.csv |
| ollama | qwen35-2b-bench | medium | 158.3969 |  | ok | ollama/summary.csv |
| ollama | qwen35-2b-bench | long | 158.0618 |  | ok | ollama/summary.csv |
