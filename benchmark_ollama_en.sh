#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
export RESULTS_ROOT="${RESULTS_ROOT:-$ROOT_DIR/results_english}"
export PROMPT_DIR="$ROOT_DIR/docker_vllm/prompts/en"
export OUT_DIR="$RESULTS_ROOT/ollama"

bash "$ROOT_DIR/ollama/benchmark_ollama_qwen35_2b.sh" "$@"
