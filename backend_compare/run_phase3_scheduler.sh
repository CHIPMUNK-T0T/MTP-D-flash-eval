#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

export RESULTS_ROOT="${RESULTS_ROOT:-$SCRIPT_DIR/results/phase3_scheduler}"
export RUNS="${RUNS:-5}"
export WARMUP_RUNS="${WARMUP_RUNS:-1}"
export CASE_SET="${CASE_SET:-core}"
export CONFIG_SET="${CONFIG_SET:-baseline}"

exec bash "$SCRIPT_DIR/benchmark_phase3_scheduler.sh" "$@"
