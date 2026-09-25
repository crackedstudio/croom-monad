#!/usr/bin/env python3
"""Pack the reference's frozen JSON vectors into a binary form Foundry can read quickly.

The JSON in `reference/croom-core/vectors/` is a frozen public interface and is never modified.
This only produces a second, faster encoding of the same data: `maths.json` alone is 700 KB of
decimal strings, and Foundry's JSON parsing is slow enough at that size to discourage running the
suite — which is the failure mode that matters, because a suite nobody runs protects nothing.

    bin/pack-vectors.py

Layout, all integers big-endian, signed values two's complement:

    header   magic   8 bytes   "CROOMFX1"
             arity   1 byte    number of inputs per record
             count   4 bytes   uint32
    record   inputs  32 bytes x arity   int256
             status  1 byte    0 ok, 1 Overflow, 2 DivByZero, 3 Domain
             output  32 bytes  int256, zero when status != 0
"""
import json
import pathlib
import sys

MAGIC = b"CROOMFX1"
STATUS = {"Overflow": 1, "DivByZero": 2, "Domain": 3}

# Which JSON keys are the inputs, in the order the function takes them.
GROUPS = {
    "exp_wad": ["input"],
    "ln_wad": ["input"],
    "inv_phi_wad": ["input"],
    "sqrt_wad": ["input"],
    "mul_div": ["a", "b", "d"],
    "u64_to_wad": ["input"],
}


def i256(value: int) -> bytes:
    """Two's complement, 32 bytes, big-endian."""
    return (value & ((1 << 256) - 1)).to_bytes(32, "big")


def pack(entries: list, input_keys: list) -> bytes:
    out = bytearray(MAGIC)
    out.append(len(input_keys))
    out += len(entries).to_bytes(4, "big")
    for entry in entries:
        for key in input_keys:
            out += i256(int(entry[key]))
        result = entry["output"]
        if result in STATUS:
            out.append(STATUS[result])
            out += i256(0)
        else:
            out.append(0)
            out += i256(int(result))
    return bytes(out)


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent.parent
    source = root / "reference/croom-core/vectors/maths.json"
    if not source.exists():
        print(f"missing {source} — run: git submodule update --init", file=sys.stderr)
        return 1

    data = json.loads(source.read_text())
    if data.get("format") != "croom-maths-vectors/1":
        print(f"unexpected vector format: {data.get('format')!r}", file=sys.stderr)
        return 1

    out_dir = root / "test/fixtures/vectors/maths"
    out_dir.mkdir(parents=True, exist_ok=True)

    total = 0
    for name, input_keys in GROUPS.items():
        entries = data[name]
        blob = pack(entries, input_keys)
        (out_dir / f"{name}.bin").write_bytes(blob)
        errors = sum(1 for e in entries if e["output"] in STATUS)
        print(f"{name:14s} {len(entries):>5} cases ({errors:>3} errors)  {len(blob):>7} bytes")
        total += len(entries)
    print(f"{'total':14s} {total:>5} cases")
    return 0


if __name__ == "__main__":
    sys.exit(main())
