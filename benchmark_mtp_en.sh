#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
export RESULTS_ROOT="${RESULTS_ROOT:-$ROOT_DIR/results_english}"
export PROMPT_DIR="$ROOT_DIR/docker_vllm/prompts/en"

bash "$ROOT_DIR/docker_vllm/mtp/benchmark_mtp_matrix.sh" "$@"
