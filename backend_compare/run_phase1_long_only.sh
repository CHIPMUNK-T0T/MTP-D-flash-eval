#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

export RESULTS_ROOT="${RESULTS_ROOT:-$SCRIPT_DIR/results/phase1_valid_long_only}"
export WORKLOAD_FILTER="${WORKLOAD_FILTER:-long_ctx8192}"
export MODE="${MODE:-phase1}"
export RUNS="${RUNS:-5}"
export WARMUP_RUNS="${WARMUP_RUNS:-1}"

exec bash "$SCRIPT_DIR/benchmark_backend.sh" "$@"
