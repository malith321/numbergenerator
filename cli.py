#!/usr/bin/env python3
"""
cli.py — Command-line client for the Prime Number Generator Service.

Usage examples
--------------
  # Find all primes between 1 and 100
  python cli.py primes 1 100

  # Show the last 10 execution records
  python cli.py history --limit 10

  # Point at a different host
  python cli.py --base-url http://localhost:9000 primes 0 50
"""

import argparse
import json
import sys
import urllib.request
import urllib.error
import urllib.parse


DEFAULT_BASE_URL = "http://localhost:8000"


def _get(url: str) -> dict:
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode()
        try:
            detail = json.loads(body).get("detail", body)
        except Exception:
            detail = body
        print(f"[ERROR {exc.code}] {detail}", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as exc:
        print(f"[CONNECTION ERROR] Could not reach the service: {exc.reason}", file=sys.stderr)
        print(f"  Is the server running at {url.split('/')[2]}?", file=sys.stderr)
        sys.exit(1)


def cmd_primes(args):
    params = urllib.parse.urlencode({"start": args.start, "end": args.end})
    url = f"{args.base_url}/primes?{params}"
    data = _get(url)

    print(f"\n{'─'*50}")
    print(f"  Range        : {data['range']['start']} – {data['range']['end']}")
    print(f"  Primes found : {data['prime_count']}")
    print(f"  Time taken   : {data['elapsed_ms']} ms")
    print(f"{'─'*50}")

    if data["primes"]:
        # Pretty-print in rows of 10
        primes = data["primes"]
        for i in range(0, len(primes), 10):
            print("  " + "  ".join(str(p) for p in primes[i : i + 10]))
    else:
        print("  (no primes in this range)")
    print()


def cmd_history(args):
    params = urllib.parse.urlencode({"limit": args.limit, "offset": args.offset})
    url = f"{args.base_url}/executions?{params}"
    data = _get(url)

    executions = data["executions"]
    if not executions:
        print("No executions recorded yet.")
        return

    # Header
    print(f"\n{'─'*72}")
    print(f"  {'ID':<5}  {'Start':>10}  {'End':>10}  {'Primes':>8}  {'ms':>8}  Executed At")
    print(f"{'─'*72}")
    for row in executions:
        print(
            f"  {row['id']:<5}  "
            f"{row['range_start']:>10}  "
            f"{row['range_end']:>10}  "
            f"{row['prime_count']:>8}  "
            f"{float(row['elapsed_ms']):>8.2f}  "
            f"{row['executed_at']}"
        )
    print(f"{'─'*72}\n")


def cmd_health(args):
    url = f"{args.base_url}/health"
    data = _get(url)
    status = data.get("status", "unknown")
    icon = "✓" if status == "ok" else "✗"
    print(f"[{icon}] Service status: {status}")


def main():
    parser = argparse.ArgumentParser(
        prog="prime-cli",
        description="CLI client for the Prime Number Generator Service.",
    )
    parser.add_argument(
        "--base-url",
        default=DEFAULT_BASE_URL,
        metavar="URL",
        dest="base_url",
        help=f"Base URL of the service (default: {DEFAULT_BASE_URL})",
    )

    sub = parser.add_subparsers(dest="command", required=True)

    # --- primes ---
    p_primes = sub.add_parser("primes", help="Generate primes in a range")
    p_primes.add_argument("start", type=int, help="Range start (inclusive, >= 0)")
    p_primes.add_argument("end", type=int, help="Range end (inclusive)")
    p_primes.set_defaults(func=cmd_primes)

    # --- history ---
    p_history = sub.add_parser("history", help="Show past execution records")
    p_history.add_argument("--limit", type=int, default=20, help="Records to show (default 20)")
    p_history.add_argument("--offset", type=int, default=0, help="Pagination offset (default 0)")
    p_history.set_defaults(func=cmd_history)

    # --- health ---
    p_health = sub.add_parser("health", help="Check service health")
    p_health.set_defaults(func=cmd_health)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
