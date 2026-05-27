#!/usr/bin/env python3
import argparse
import json
import time
import urllib.error
import urllib.request
from pathlib import Path


def request_once(url: str, payload: dict, timeout: int) -> tuple[dict, int]:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    start = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        raise RuntimeError(raw.decode("utf-8", errors="replace")) from exc
    elapsed_ms = int((time.time() - start) * 1000)
    return json.loads(raw), elapsed_ms


def extract_text(data: dict) -> str:
    choices = data.get("choices", [])
    if not choices:
        return ""
    choice = choices[0]
    message = choice.get("message", {})
    return message.get("content", choice.get("text", "")) or ""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--prompt-file", required=True)
    parser.add_argument("--max-tokens", type=int, required=True)
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--warmup-runs", type=int, default=1)
    parser.add_argument("--timeout", type=int, default=420)
    parser.add_argument("--response-dir", required=True)
    parser.add_argument("--summary-json", required=True)
    args = parser.parse_args()

    prompt = Path(args.prompt_file).read_text(encoding="utf-8")
    payload = {
        "model": args.model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": args.max_tokens,
        "temperature": 0,
        "chat_template_kwargs": {"enable_thinking": False},
    }

    response_dir = Path(args.response_dir)
    response_dir.mkdir(parents=True, exist_ok=True)

    warmups = []
    try:
        for idx in range(1, args.warmup_runs + 1):
            data, elapsed_ms = request_once(args.url, payload, args.timeout)
            if "error" in data:
                raise RuntimeError(data["error"])
            usage = data.get("usage", {})
            tokens = int(usage.get("completion_tokens", 0) or 0)
            prompt_tokens = int(usage.get("prompt_tokens", 0) or 0)
            total_tokens = int(usage.get("total_tokens", 0) or 0)
            (response_dir / f"warmup{idx}.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            (response_dir / f"warmup{idx}.txt").write_text(extract_text(data), encoding="utf-8")
            warmups.append({
                "run_index": idx,
                "elapsed_ms": elapsed_ms,
                "prompt_tokens": prompt_tokens,
                "completion_tokens": tokens,
                "total_tokens": total_tokens,
            })

        runs = []
        for idx in range(1, args.runs + 1):
            data, elapsed_ms = request_once(args.url, payload, args.timeout)
            if "error" in data:
                raise RuntimeError(data["error"])
            usage = data.get("usage", {})
            tokens = int(usage.get("completion_tokens", 0) or 0)
            prompt_tokens = int(usage.get("prompt_tokens", 0) or 0)
            total_tokens = int(usage.get("total_tokens", 0) or 0)
            tok_per_s = tokens / (elapsed_ms / 1000) if elapsed_ms else 0.0
            (response_dir / f"run{idx}.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            (response_dir / f"run{idx}.txt").write_text(extract_text(data), encoding="utf-8")
            runs.append({
                "run_index": idx,
                "elapsed_ms": elapsed_ms,
                "prompt_tokens": prompt_tokens,
                "completion_tokens": tokens,
                "total_tokens": total_tokens,
                "tok_per_s": tok_per_s,
            })
    except Exception as exc:
        error = {"status": "error", "message": str(exc), "prompt_file": args.prompt_file, "max_tokens": args.max_tokens}
        (response_dir / "error.json").write_text(json.dumps(error, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        (response_dir / "error.txt").write_text(str(exc) + "\n", encoding="utf-8")
        raise

    tps_values = sorted(r["tok_per_s"] for r in runs)
    elapsed_values = sorted(r["elapsed_ms"] for r in runs)
    mid = len(runs) // 2
    if len(runs) % 2:
        median_tps = tps_values[mid]
        median_elapsed = elapsed_values[mid]
    else:
        median_tps = (tps_values[mid - 1] + tps_values[mid]) / 2
        median_elapsed = (elapsed_values[mid - 1] + elapsed_values[mid]) / 2

    prompt_token_values = [r["prompt_tokens"] for r in runs if r.get("prompt_tokens")]
    prompt_tokens = prompt_token_values[0] if prompt_token_values else 0

    summary = {
        "model": args.model,
        "prompt_file": args.prompt_file,
        "prompt_tokens": prompt_tokens,
        "max_tokens": args.max_tokens,
        "warmup_runs_excluded": args.warmup_runs,
        "measured_runs": args.runs,
        "median_elapsed_ms": median_elapsed,
        "median_tok_per_s": median_tps,
        "warmups": warmups,
        "runs": runs,
        "status": "ok",
    }
    Path(args.summary_json).write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
