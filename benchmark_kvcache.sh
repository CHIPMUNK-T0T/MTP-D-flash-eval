#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
export RESULTS_ROOT="${RESULTS_ROOT:-$ROOT_DIR/results_kvcache}"
export PROMPT_DIR="${PROMPT_DIR:-$ROOT_DIR/docker_vllm/prompts}"

if [ "${1:-}" = "--dry-run" ]; then
  bash "$ROOT_DIR/docker_vllm/kvcache/benchmark_kvcache.sh" --dry-run
else
  bash "$ROOT_DIR/docker_vllm/kvcache/benchmark_kvcache.sh" "$@"
fi
