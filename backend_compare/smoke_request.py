#!/usr/bin/env python3
import argparse
import json
import time
import urllib.error
import urllib.request


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--prompt-file", required=True)
    parser.add_argument("--max-tokens", type=int, default=32)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--output-text", required=True)
    parser.add_argument("--summary", required=True)
    args = parser.parse_args()

    with open(args.prompt_file, encoding="utf-8") as f:
        prompt = f.read()

    payload = {
        "model": args.model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": args.max_tokens,
        "temperature": 0,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        args.url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    start = time.time()
    try:
        with urllib.request.urlopen(req, timeout=420) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        with open(args.output_json, "wb") as f:
            f.write(raw)
        raise
    elapsed_ms = int((time.time() - start) * 1000)

    with open(args.output_json, "wb") as f:
        f.write(raw)

    data = json.loads(raw)
    if "error" in data:
        raise RuntimeError(data["error"])

    usage = data.get("usage", {})
    completion_tokens = usage.get("completion_tokens", 0)
    choices = data.get("choices", [])
    text = ""
    if choices:
        message = choices[0].get("message", {})
        text = message.get("content", choices[0].get("text", "")) or ""

    with open(args.output_text, "w", encoding="utf-8") as f:
        f.write(text)

    summary = {
        "model": args.model,
        "elapsed_ms": elapsed_ms,
        "completion_tokens": completion_tokens,
        "tok_per_s": completion_tokens / (elapsed_ms / 1000) if elapsed_ms else 0,
        "status": "ok",
    }
    with open(args.summary, "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
