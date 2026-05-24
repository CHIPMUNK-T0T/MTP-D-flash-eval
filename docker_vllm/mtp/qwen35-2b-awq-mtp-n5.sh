#!/bin/bash
# Qwen3.5-2B AWQ4 + qwen3_next_mtp (num_speculative_tokens=5)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NUM_SPECULATIVE_TOKENS=5 bash "$SCRIPT_DIR/qwen35-2b-awq-mtp-n3.sh"
