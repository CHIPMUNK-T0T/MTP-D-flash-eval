#!/usr/bin/env python3
import argparse
import json
import math
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
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


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    rank = max(1, math.ceil((pct / 100.0) * len(ordered)))
    return float(ordered[rank - 1])


def median(values: list[float]) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    mid = len(ordered) // 2
    if len(ordered) % 2:
        return float(ordered[mid])
    return float((ordered[mid - 1] + ordered[mid]) / 2)


def run_one_request(args, payload: dict, response_dir: Path, batch_index: int, request_index: int, phase: str) -> dict:
    name = f"{phase}_batch{batch_index}_req{request_index}"
    try:
        data, elapsed_ms = request_once(args.url, payload, args.timeout)
        if "error" in data:
            raise RuntimeError(json.dumps(data["error"], ensure_ascii=False))
        usage = data.get("usage", {})
        completion_tokens = int(usage.get("completion_tokens", 0) or 0)
        prompt_tokens = int(usage.get("prompt_tokens", 0) or 0)
        total_tokens = int(usage.get("total_tokens", 0) or 0)
        tok_per_s = completion_tokens / (elapsed_ms / 1000) if elapsed_ms else 0.0
        (response_dir / f"{name}.json").write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        (response_dir / f"{name}.txt").write_text(extract_text(data), encoding="utf-8")
        return {
            "batch_index": batch_index,
            "request_index": request_index,
            "status": "ok",
            "elapsed_ms": elapsed_ms,
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": total_tokens,
            "tok_per_s": tok_per_s,
        }
    except Exception as exc:
        error = {
            "batch_index": batch_index,
            "request_index": request_index,
            "status": "error",
            "message": str(exc),
        }
        (response_dir / f"{name}_error.json").write_text(
            json.dumps(error, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        return {
            "batch_index": batch_index,
            "request_index": request_index,
            "status": "error",
            "elapsed_ms": 0,
            "prompt_tokens": 0,
            "completion_tokens": 0,
            "total_tokens": 0,
            "tok_per_s": 0.0,
            "error": str(exc),
        }


def run_batch(args, payload: dict, response_dir: Path, batch_index: int, phase: str) -> dict:
    start = time.time()
    requests = []
    with ThreadPoolExecutor(max_workers=args.concurrency) as executor:
        futures = [
            executor.submit(run_one_request, args, payload, response_dir, batch_index, idx, phase)
            for idx in range(1, args.concurrency + 1)
        ]
        for future in as_completed(futures):
            requests.append(future.result())
    batch_elapsed_ms = int((time.time() - start) * 1000)
    requests.sort(key=lambda item: item["request_index"])
    success = [r for r in requests if r["status"] == "ok"]
    completion_tokens = sum(r["completion_tokens"] for r in success)
    aggregate_tok_per_s = completion_tokens / (batch_elapsed_ms / 1000) if batch_elapsed_ms else 0.0
    return {
        "batch_index": batch_index,
        "phase": phase,
        "concurrency": args.concurrency,
        "batch_elapsed_ms": batch_elapsed_ms,
        "success_count": len(success),
        "failure_count": len(requests) - len(success),
        "completion_tokens": completion_tokens,
        "total_tokens": sum(r["total_tokens"] for r in success),
        "aggregate_tok_per_s": aggregate_tok_per_s,
        "requests": requests,
    }


def read_prompt(path: str, char_limit: int) -> str:
    prompt = Path(path).read_text(encoding="utf-8")
    if char_limit > 0:
        prompt = prompt[:char_limit].rstrip()
    return prompt


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--prompt-file", required=True)
    parser.add_argument("--prompt-char-limit", type=int, default=0)
    parser.add_argument("--max-tokens", type=int, required=True)
    parser.add_argument("--concurrency", type=int, required=True)
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--warmup-runs", type=int, default=1)
    parser.add_argument("--timeout", type=int, default=420)
    parser.add_argument("--response-dir", required=True)
    parser.add_argument("--summary-json", required=True)
    args = parser.parse_args()

    prompt = read_prompt(args.prompt_file, args.prompt_char_limit)
    payload = {
        "model": args.model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": args.max_tokens,
        "temperature": 0,
        "chat_template_kwargs": {"enable_thinking": False},
    }

    response_dir = Path(args.response_dir)
    response_dir.mkdir(parents=True, exist_ok=True)

    warmups = [
        run_batch(args, payload, response_dir, idx, "warmup")
        for idx in range(1, args.warmup_runs + 1)
    ]
    runs = [
        run_batch(args, payload, response_dir, idx, "run")
        for idx in range(1, args.runs + 1)
    ]

    measured_requests = [req for batch in runs for req in batch["requests"]]
    successful_requests = [req for req in measured_requests if req["status"] == "ok"]
    failed_requests = [req for req in measured_requests if req["status"] != "ok"]
    prompt_token_values = [req["prompt_tokens"] for req in successful_requests if req.get("prompt_tokens")]

    summary = {
        "model": args.model,
        "prompt_file": args.prompt_file,
        "prompt_char_limit": args.prompt_char_limit,
        "prompt_tokens": prompt_token_values[0] if prompt_token_values else 0,
        "max_tokens": args.max_tokens,
        "concurrency": args.concurrency,
        "warmup_runs_excluded": args.warmup_runs,
        "measured_runs": args.runs,
        "total_requests": len(measured_requests),
        "success_count": len(successful_requests),
        "failure_count": len(failed_requests),
        "status": "ok" if not failed_requests else ("partial_failed" if successful_requests else "request_failed"),
        "median_batch_elapsed_ms": median([b["batch_elapsed_ms"] for b in runs]),
        "p95_request_elapsed_ms": percentile([r["elapsed_ms"] for r in successful_requests], 95),
        "median_request_elapsed_ms": median([r["elapsed_ms"] for r in successful_requests]),
        "median_aggregate_tok_per_s": median([b["aggregate_tok_per_s"] for b in runs]),
        "median_request_tok_per_s": median([r["tok_per_s"] for r in successful_requests]),
        "warmups": warmups,
        "runs": runs,
    }
    Path(args.summary_json).write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
