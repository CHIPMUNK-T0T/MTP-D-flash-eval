# Ollama qwen3.5:2b Benchmark Summary

vLLMとはAPIと計測方法が異なるため、この記事では参考値として扱う。

| Engine | Model | Workload | Output tokens | Eval tok/s median | Total tok/s median | Prompt tok/s median | Total latency ms | Notes |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| ollama | qwen35-2b-bench | medium | 256 | 155.92 | 136.82 | 4537.63 | 1871 |  |
| ollama | qwen35-2b-bench | long | 512 | 155.89 | 142.77 | 5629.36 | 3586 |  |
