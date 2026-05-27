# Qwen3.5-4B KV Cache Benchmark Summary

Model: `RedHatAI/Qwen3.5-4B-FP8-dynamic`, `--enforce-eager`, max-num-batched-tokens 4096, concurrency 1, throwaway warmup 1 + TTFT(streaming) 1 + measured 5.

Status legend: `ok`=success, `ctx_too_long`=prompt exceeded max_model_len, `oom`=CUDA out of memory at startup, `model_limit`=vLLM ValueError at startup.

## medium

| Config | kv_cache_dtype | max_model_len | tok/s | vs KV0 | TTFT ms | KV tokens | Status |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| base_fa | auto | 2048 | 60.18 | 1.000x | 83 | 51200 | ok |
| base_fi | auto | 2048 | 60.26 | 1.001x | 80 | 51200 | ok |
| base_fi_8k | auto | 8192 | 60.16 | 1.000x | 80 | 75452 | ok |
| base_fi_32k | auto | 32768 | 60.05 | 0.998x | 80 | 86884 | ok |
| base_fi_64k | auto | 65536 | 60.04 | 0.998x | 80 | 89600 | ok |
| base_fi_96k | auto | 98304 |  |  |  |  | model_limit |
| fp8kv_2k | fp8 | 2048 | 60.16 | 1.000x | 87 | 71680 | ok |
| fp8kv_8k | fp8 | 8192 | 60.09 | 0.999x | 80 | 130327 | ok |
| fp8kv_32k | fp8 | 32768 | 59.98 | 0.997x | 80 | 163840 | ok |
| fp8kv_64k | fp8 | 65536 | 59.98 | 0.997x | 82 | 173769 | ok |
| fp8kv_96k | fp8 | 98304 | 59.97 | 0.996x | 79 | 177352 | ok |

## long

| Config | kv_cache_dtype | max_model_len | tok/s | vs KV0 | TTFT ms | KV tokens | Status |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| base_fa | auto | 2048 | 60.30 | 1.000x | 63 | 51200 | ok |
| base_fi | auto | 2048 | 60.39 | 1.002x | 60 | 51200 | ok |
| base_fi_8k | auto | 8192 | 60.28 | 1.000x | 60 | 75452 | ok |
| base_fi_32k | auto | 32768 | 60.20 | 0.998x | 60 | 86884 | ok |
| base_fi_64k | auto | 65536 | 60.15 | 0.998x | 60 | 89600 | ok |
| base_fi_96k | auto | 98304 |  |  |  |  | model_limit |
| fp8kv_2k | fp8 | 2048 | 60.33 | 1.000x | 61 | 71680 | ok |
| fp8kv_8k | fp8 | 8192 | 60.26 | 0.999x | 61 | 130327 | ok |
| fp8kv_32k | fp8 | 32768 | 60.13 | 0.997x | 60 | 163840 | ok |
| fp8kv_64k | fp8 | 65536 | 60.14 | 0.997x | 60 | 173769 | ok |
| fp8kv_96k | fp8 | 98304 | 60.13 | 0.997x | 60 | 177352 | ok |

## ctx_long

| Config | kv_cache_dtype | max_model_len | tok/s | vs KV0 | TTFT ms | KV tokens | Status |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| base_fa | auto | 2048 | 58.57 | 1.000x | 143 | 51200 | ok |
| base_fi | auto | 2048 | 58.69 | 1.002x | 146 | 51200 | ok |
| base_fi_8k | auto | 8192 | 58.66 | 1.002x | 141 | 75452 | ok |
| base_fi_32k | auto | 32768 | 58.55 | 1.000x | 146 | 86884 | ok |
| base_fi_64k | auto | 65536 | 58.51 | 0.999x | 141 | 89600 | ok |
| base_fi_96k | auto | 98304 |  |  |  |  | model_limit |
| fp8kv_2k | fp8 | 2048 | 58.80 | 1.004x | 145 | 71680 | ok |
| fp8kv_8k | fp8 | 8192 | 58.63 | 1.001x | 142 | 130327 | ok |
| fp8kv_32k | fp8 | 32768 | 58.51 | 0.999x | 143 | 163840 | ok |
| fp8kv_64k | fp8 | 65536 | 58.61 | 1.001x | 145 | 173769 | ok |
| fp8kv_96k | fp8 | 98304 | 58.54 | 1.000x | 149 | 177352 | ok |

## ctx_8k

| Config | kv_cache_dtype | max_model_len | tok/s | vs KV0 | TTFT ms | KV tokens | Status |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| base_fa | auto | 2048 |  |  | -1 | 51200 | ctx_too_long |
| base_fi | auto | 2048 |  |  | -1 | 51200 | ctx_too_long |
| base_fi_8k | auto | 8192 | 43.73 |  | 773 | 75452 | ok |
| base_fi_32k | auto | 32768 | 43.66 |  | 773 | 86884 | ok |
| base_fi_64k | auto | 65536 | 43.54 |  | 773 | 89600 | ok |
| base_fi_96k | auto | 98304 |  |  |  |  | model_limit |
| fp8kv_2k | fp8 | 2048 |  |  | -1 | 71680 | ctx_too_long |
| fp8kv_8k | fp8 | 8192 | 43.37 |  | 782 | 130327 | ok |
| fp8kv_32k | fp8 | 32768 | 43.31 |  | 786 | 163840 | ok |
| fp8kv_64k | fp8 | 65536 | 43.26 |  | 787 | 173769 | ok |
| fp8kv_96k | fp8 | 98304 | 43.29 |  | 781 | 177352 | ok |

## ctx_32k

| Config | kv_cache_dtype | max_model_len | tok/s | vs KV0 | TTFT ms | KV tokens | Status |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| base_fa | auto | 2048 |  |  | -1 | 51200 | ctx_too_long |
| base_fi | auto | 2048 |  |  | -1 | 51200 | ctx_too_long |
| base_fi_8k | auto | 8192 |  |  | -1 | 75452 | ctx_too_long |
| base_fi_32k | auto | 32768 | 24.19 |  | 2762 | 86884 | ok |
| base_fi_64k | auto | 65536 | 24.19 |  | 2761 | 89600 | ok |
| base_fi_96k | auto | 98304 |  |  |  |  | model_limit |
| fp8kv_2k | fp8 | 2048 |  |  | -1 | 71680 | ctx_too_long |
| fp8kv_8k | fp8 | 8192 |  |  | -1 | 130327 | ctx_too_long |
| fp8kv_32k | fp8 | 32768 | 23.59 |  | 2896 | 163840 | ok |
| fp8kv_64k | fp8 | 65536 | 23.58 |  | 2894 | 173769 | ok |
| fp8kv_96k | fp8 | 98304 | 23.57 |  | 2894 | 177352 | ok |

