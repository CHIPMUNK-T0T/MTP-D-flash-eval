# Ollama qwen3.5:2b Benchmark Summary

vLLMとはAPIと計測方法が異なるため、この記事では参考値として扱う。

| Engine | Model | Workload | Output tokens | Eval tok/s median | Total tok/s median | Prompt tok/s median | Total latency ms | Notes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| ollama | qwen35-2b-bench | medium | 256 | 158.40 | 139.85 | 4437.24 | 1831 |  |
| ollama | qwen35-2b-bench | long | 512 | 158.06 | 144.52 | 5637.34 | 3543 |  |
