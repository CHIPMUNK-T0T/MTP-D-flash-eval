#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
export RESULTS_ROOT="${RESULTS_ROOT:-$ROOT_DIR/results_english}"
export PROMPT_DIR="$ROOT_DIR/docker_vllm/prompts/en"
MODE="${1:-}"

if [ "$MODE" = "--dry-run" ]; then
  bash "$ROOT_DIR/benchmark_mtp_en.sh" --dry-run
  bash "$ROOT_DIR/benchmark_dflash_en.sh" --dry-run
  bash "$ROOT_DIR/benchmark_ollama_en.sh" --dry-run
  exit 0
fi

if [ "$MODE" != "--summary-only" ]; then
  bash "$ROOT_DIR/benchmark_mtp_en.sh"
  bash "$ROOT_DIR/benchmark_dflash_en.sh"
  bash "$ROOT_DIR/benchmark_ollama_en.sh"
fi

python3 - "$RESULTS_ROOT" <<'PY'
import csv
import sys
from pathlib import Path

results_root = Path(sys.argv[1])
summary_csv = results_root / "summary.csv"
summary_md = results_root / "summary.md"

rows = []

def add_row(suite, config_id, label, workload, max_tokens, tok_s, acceptance, status, source, notes):
    rows.append({
        "suite": suite,
        "config_id": config_id,
        "label": label,
        "workload": workload,
        "max_tokens": max_tokens,
        "median_tok_per_s": tok_s,
        "acceptance_rate": acceptance,
        "status": status,
        "source": source,
        "notes": notes,
    })

def read_csv(path):
    if not path.exists():
        return []
    with path.open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))

for path in [results_root / "mtp" / "summary.csv"]:
    for row in read_csv(path):
        add_row(
            "2b-mtp",
            row.get("config_id", ""),
            row.get("label", ""),
            row.get("workload", ""),
            row.get("max_tokens", ""),
            row.get("median_tok_per_s", ""),
            row.get("acceptance_rate", ""),
            row.get("status", ""),
            str(path.relative_to(results_root)),
            row.get("notes", ""),
        )

for path, suite in [
    (results_root / "d-flash" / "summary.csv", "4b-dflash"),
    (results_root / "d-flash" / "mtp_summary.csv", "4b-mtp"),
]:
    for row in read_csv(path):
        add_row(
            suite,
            row.get("config_id", ""),
            row.get("label", ""),
            row.get("workload", ""),
            row.get("max_tokens", ""),
            row.get("median_tok_per_s", ""),
            row.get("acceptance_rate", ""),
            row.get("status", ""),
            str(path.relative_to(results_root)),
            row.get("notes", ""),
        )

for path in [results_root / "ollama" / "summary.csv"]:
    for row in read_csv(path):
        add_row(
            "ollama",
            row.get("model", ""),
            row.get("model", ""),
            row.get("workload", ""),
            row.get("max_tokens", ""),
            row.get("median_eval_tok_per_s", ""),
            "",
            row.get("status", ""),
            str(path.relative_to(results_root)),
            row.get("notes", ""),
        )

results_root.mkdir(parents=True, exist_ok=True)
with summary_csv.open("w", encoding="utf-8", newline="") as f:
    fieldnames = [
        "suite", "config_id", "label", "workload", "max_tokens",
        "median_tok_per_s", "acceptance_rate", "status", "source", "notes",
    ]
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)

with summary_md.open("w", encoding="utf-8") as f:
    f.write("# Benchmark Summary (English prompts)\n\n")
    f.write("Generated after `benchmark_all_english.sh` completes.\n\n")
    f.write("| Suite | Config | Workload | tok/s median | Acceptance | Status | Source |\n")
    f.write("| --- | --- | --- | ---: | ---: | --- | --- |\n")
    for row in rows:
        f.write(
            f"| {row['suite']} | {row['config_id']} | {row['workload']} | "
            f"{row['median_tok_per_s']} | {row['acceptance_rate']} | "
            f"{row['status']} | {row['source']} |\n"
        )

print(f"summary generated: {summary_csv}")
print(f"summary generated: {summary_md}")
PY
