#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

export RESULTS_ROOT="${RESULTS_ROOT:-$SCRIPT_DIR/results/phase2_load}"
export RUNS="${RUNS:-5}"
export WARMUP_RUNS="${WARMUP_RUNS:-1}"

exec bash "$SCRIPT_DIR/benchmark_phase2_load.sh" "$@"
