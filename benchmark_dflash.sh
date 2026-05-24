#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
export RESULTS_ROOT="${RESULTS_ROOT:-$ROOT_DIR/results}"
export PROMPT_DIR="${PROMPT_DIR:-$ROOT_DIR/docker_vllm/prompts}"

if [ "${1:-}" = "--dry-run" ]; then
  bash "$ROOT_DIR/docker_vllm/dflash/benchmark_dflash_4b.sh" --dry-run
  bash "$ROOT_DIR/docker_vllm/dflash/benchmark_4b_mtp_compare.sh" --dry-run
else
  bash "$ROOT_DIR/docker_vllm/dflash/benchmark_dflash_4b.sh" "$@"
  bash "$ROOT_DIR/docker_vllm/dflash/benchmark_4b_mtp_compare.sh"
fi
