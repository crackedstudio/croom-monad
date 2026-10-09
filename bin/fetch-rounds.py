#!/usr/bin/env python3
"""Fetch consecutive drand evmnet rounds into a JSON fixture.

    bin/fetch-rounds.py <start> <count> <out.json>

The ladder's fraud proof verifies a signature for a specific round, so an epoch of adjacent
rounds needs adjacent signatures. The API rate-limits bursts, hence the retries.
"""
import json
import pathlib
import sys
import time
import urllib.request

CHAIN = "04f1e9062b8a81f848fded9c12306733282b2727ecced50032187751166ec8c3"


def fetch(round_number: int) -> str:
    url = f"https://api.drand.sh/v2/chains/{CHAIN}/rounds/{round_number}"
    for attempt in range(5):
        try:
            with urllib.request.urlopen(url, timeout=20) as f:
                return json.load(f)["signature"]
        except Exception as exc:  # noqa: BLE001 - any failure is retried
            if attempt == 4:
                raise SystemExit(f"round {round_number}: {exc}")
            time.sleep(2 * (attempt + 1))
    raise SystemExit("unreachable")


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    start, count, out = int(sys.argv[1]), int(sys.argv[2]), pathlib.Path(sys.argv[3])

    sigs = []
    for i in range(count):
        sigs.append(fetch(start + i))
        print(f"\r  {i + 1}/{count}", end="", file=sys.stderr, flush=True)
    print(file=sys.stderr)

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({
        "chain_hash": CHAIN,
        "start": start,
        "count": count,
        "signatures": sigs,
    }, indent=2) + "\n")
    print(f"{out}: rounds {start}..{start + count - 1}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
