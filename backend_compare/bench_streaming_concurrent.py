#!/usr/bin/env python3
import argparse
import json
import math
import statistics
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    rank = max(1, math.ceil((pct / 100.0) * len(ordered)))
    return float(ordered[rank - 1])


def median(values: list[float]) -> float:
    if not values:
        return 0.0
    return float(statistics.median(values))


def read_prompt(path: str, char_limit: int) -> str:
    prompt = Path(path).read_text(encoding="utf-8")
    if char_limit > 0:
        prompt = prompt[:char_limit].rstrip()
    return prompt


def parse_prompt_specs(specs: str) -> list[dict]:
    requests: list[dict] = []
    for raw_spec in specs.split(";"):
        raw_spec = raw_spec.strip()
        if not raw_spec:
            continue
        try:
            profile, prompt_file, char_limit, count = raw_spec.rsplit(":", 3)
        except ValueError as exc:
            raise ValueError(
                "prompt spec must be 'profile:/path/to/prompt.txt:char_limit:count'"
            ) from exc
        prompt = read_prompt(prompt_file, int(char_limit))
        for _ in range(int(count)):
            requests.append(
                {
                    "profile": profile,
                    "prompt_file": prompt_file,
                    "prompt_char_limit": int(char_limit),
                    "prompt": prompt,
                }
            )
    return requests


def extract_delta_content(chunk: dict) -> str:
    choices = chunk.get("choices", [])
    if not choices:
        return ""
    choice = choices[0]
    delta = choice.get("delta", {})
    return delta.get("content", choice.get("text", "")) or ""


def request_stream_once(args, prompt_def: dict, response_dir: Path, batch_index: int, request_index: int, phase: str) -> dict:
    payload = {
        "model": args.model,
        "messages": [{"role": "user", "content": prompt_def["prompt"]}],
        "max_tokens": args.max_tokens,
        "temperature": 0,
        "stream": True,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        args.url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    name = f"{phase}_batch{batch_index}_req{request_index}_{prompt_def['profile']}"
    start = time.time()
    first_content_at = 0.0
    previous_content_at = 0.0
    content_chunks = 0
    itl_ms_values: list[float] = []
    text_parts: list[str] = []
    raw_events: list[dict] = []
    usage = {}

    try:
        with urllib.request.urlopen(req, timeout=args.timeout) as resp:
            for raw_line in resp:
                line = raw_line.decode("utf-8", errors="replace").strip()
                if not line or not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                try:
                    chunk = json.loads(data)
                except json.JSONDecodeError:
                    raw_events.append({"malformed": data})
                    continue
                raw_events.append(chunk)
                if chunk.get("usage"):
                    usage = chunk["usage"]
                content = extract_delta_content(chunk)
                if not content:
                    continue
                now = time.time()
                if first_content_at == 0.0:
                    first_content_at = now
                if previous_content_at:
                    itl_ms_values.append((now - previous_content_at) * 1000)
                previous_content_at = now
                content_chunks += 1
                text_parts.append(content)
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        error = {
            "batch_index": batch_index,
            "request_index": request_index,
            "profile": prompt_def["profile"],
            "status": "error",
            "message": raw,
        }
        (response_dir / f"{name}_error.json").write_text(
            json.dumps(error, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        return error | {
            "elapsed_ms": 0,
            "ttft_ms": 0.0,
            "mean_itl_ms": 0.0,
            "p50_itl_ms": 0.0,
            "p95_itl_ms": 0.0,
            "prompt_tokens": 0,
            "completion_tokens": 0,
            "completion_units": 0,
            "tok_per_s": 0.0,
        }
    except Exception as exc:
        error = {
            "batch_index": batch_index,
            "request_index": request_index,
            "profile": prompt_def["profile"],
            "status": "error",
            "message": str(exc),
        }
        (response_dir / f"{name}_error.json").write_text(
            json.dumps(error, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        return error | {
            "elapsed_ms": 0,
            "ttft_ms": 0.0,
            "mean_itl_ms": 0.0,
            "p50_itl_ms": 0.0,
            "p95_itl_ms": 0.0,
            "prompt_tokens": 0,
            "completion_tokens": 0,
            "completion_units": 0,
            "tok_per_s": 0.0,
        }

    elapsed_ms = int((time.time() - start) * 1000)
    ttft_ms = (first_content_at - start) * 1000 if first_content_at else 0.0
    completion_tokens = int(usage.get("completion_tokens", 0) or 0)
    prompt_tokens = int(usage.get("prompt_tokens", 0) or 0)
    total_tokens = int(usage.get("total_tokens", 0) or 0)
    completion_units = completion_tokens if completion_tokens else content_chunks
    tok_per_s = completion_units / (elapsed_ms / 1000) if elapsed_ms else 0.0
    result = {
        "batch_index": batch_index,
        "request_index": request_index,
        "profile": prompt_def["profile"],
        "prompt_file": prompt_def["prompt_file"],
        "prompt_char_limit": prompt_def["prompt_char_limit"],
        "status": "ok",
        "elapsed_ms": elapsed_ms,
        "ttft_ms": ttft_ms,
        "mean_itl_ms": statistics.mean(itl_ms_values) if itl_ms_values else 0.0,
        "p50_itl_ms": median(itl_ms_values),
        "p95_itl_ms": percentile(itl_ms_values, 95),
        "content_chunks": content_chunks,
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "total_tokens": total_tokens,
        "completion_units": completion_units,
        "tok_per_s": tok_per_s,
    }
    (response_dir / f"{name}.json").write_text(
        json.dumps({"result": result, "events": raw_events}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (response_dir / f"{name}.txt").write_text("".join(text_parts), encoding="utf-8")
    return result


def run_batch(args, prompt_defs: list[dict], response_dir: Path, batch_index: int, phase: str) -> dict:
    start = time.time()
    requests = []
    with ThreadPoolExecutor(max_workers=args.concurrency) as executor:
        futures = [
            executor.submit(request_stream_once, args, prompt_def, response_dir, batch_index, idx, phase)
            for idx, prompt_def in enumerate(prompt_defs, start=1)
        ]
        for future in as_completed(futures):
            requests.append(future.result())
    batch_elapsed_ms = int((time.time() - start) * 1000)
    requests.sort(key=lambda item: item["request_index"])
    success = [r for r in requests if r["status"] == "ok"]
    completion_units = sum(r["completion_units"] for r in success)
    aggregate_tok_per_s = completion_units / (batch_elapsed_ms / 1000) if batch_elapsed_ms else 0.0
    return {
        "batch_index": batch_index,
        "phase": phase,
        "concurrency": args.concurrency,
        "batch_elapsed_ms": batch_elapsed_ms,
        "success_count": len(success),
        "failure_count": len(requests) - len(success),
        "completion_units": completion_units,
        "aggregate_tok_per_s": aggregate_tok_per_s,
        "requests": requests,
    }


def profile_summary(requests: list[dict]) -> dict:
    grouped: dict[str, list[dict]] = {}
    for req in requests:
        if req["status"] == "ok":
            grouped.setdefault(req["profile"], []).append(req)
    summary = {}
    for profile, items in grouped.items():
        summary[profile] = {
            "count": len(items),
            "prompt_tokens": median([r["prompt_tokens"] for r in items if r["prompt_tokens"]]),
            "p50_ttft_ms": median([r["ttft_ms"] for r in items]),
            "p95_ttft_ms": percentile([r["ttft_ms"] for r in items], 95),
            "p50_itl_ms": median([r["p50_itl_ms"] for r in items]),
            "p95_itl_ms": percentile([r["p95_itl_ms"] for r in items], 95),
            "p50_elapsed_ms": median([r["elapsed_ms"] for r in items]),
            "p95_elapsed_ms": percentile([r["elapsed_ms"] for r in items], 95),
        }
    return summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--prompt-specs", required=True)
    parser.add_argument("--max-tokens", type=int, required=True)
    parser.add_argument("--concurrency", type=int, required=True)
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--warmup-runs", type=int, default=1)
    parser.add_argument("--timeout", type=int, default=420)
    parser.add_argument("--response-dir", required=True)
    parser.add_argument("--summary-json", required=True)
    args = parser.parse_args()

    prompt_defs = parse_prompt_specs(args.prompt_specs)
    if len(prompt_defs) != args.concurrency:
        raise ValueError(
            f"prompt spec count ({len(prompt_defs)}) must match concurrency ({args.concurrency})"
        )

    response_dir = Path(args.response_dir)
    response_dir.mkdir(parents=True, exist_ok=True)

    warmups = [
        run_batch(args, prompt_defs, response_dir, idx, "warmup")
        for idx in range(1, args.warmup_runs + 1)
    ]
    runs = [
        run_batch(args, prompt_defs, response_dir, idx, "run")
        for idx in range(1, args.runs + 1)
    ]

    measured_requests = [req for batch in runs for req in batch["requests"]]
    successful_requests = [req for req in measured_requests if req["status"] == "ok"]
    failed_requests = [req for req in measured_requests if req["status"] != "ok"]
    summary = {
        "model": args.model,
        "prompt_specs": args.prompt_specs,
        "max_tokens": args.max_tokens,
        "concurrency": args.concurrency,
        "warmup_runs_excluded": args.warmup_runs,
        "measured_runs": args.runs,
        "total_requests": len(measured_requests),
        "success_count": len(successful_requests),
        "failure_count": len(failed_requests),
        "status": "ok" if not failed_requests else ("partial_failed" if successful_requests else "request_failed"),
        "median_batch_elapsed_ms": median([b["batch_elapsed_ms"] for b in runs]),
        "median_aggregate_tok_per_s": median([b["aggregate_tok_per_s"] for b in runs]),
        "p50_request_elapsed_ms": median([r["elapsed_ms"] for r in successful_requests]),
        "p95_request_elapsed_ms": percentile([r["elapsed_ms"] for r in successful_requests], 95),
        "p50_ttft_ms": median([r["ttft_ms"] for r in successful_requests]),
        "p95_ttft_ms": percentile([r["ttft_ms"] for r in successful_requests], 95),
        "p50_itl_ms": median([r["p50_itl_ms"] for r in successful_requests]),
        "p95_itl_ms": percentile([r["p95_itl_ms"] for r in successful_requests], 95),
        "median_request_tok_per_s": median([r["tok_per_s"] for r in successful_requests]),
        "profile_summary": profile_summary(successful_requests),
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
