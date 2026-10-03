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


# Families the EVM port ships. The reference implements all eight; see
# docs/decisions/0002-scope.md for why only these.
FAMILIES = ["drift", "step"]

ROUND_MAGIC = b"CROOMRND"


def i128(value: int) -> bytes:
    """Two's complement, 16 bytes, big-endian — the width the reference encodes `i128` at."""
    return (value & ((1 << 128) - 1)).to_bytes(16, "big")


def pack_rounds(rounds: list) -> bytes:
    """One record per round: the beacon value in, the full state out.

    153 bytes each, so 10,000 rounds is 1.5 MB — small enough to read in one go and orders of
    magnitude faster than parsing 3 MB of decimal strings inside Foundry.
    """
    out = bytearray(ROUND_MAGIC)
    out += len(rounds).to_bytes(4, "big")
    for r in rounds:
        out += int(r["round"]).to_bytes(8, "big")
        out += bytes.fromhex(r["r"])
        out += i128(int(r["close"]))
        out += i128(int(r["high"]))
        out += i128(int(r["low"]))
        out.append(int(r["level"]))
        out += i128(int(r["lo"]))
        out += i128(int(r["hi"]))
        out += bytes.fromhex(r["state_hash"])
    return bytes(out)


def pack_families(root: pathlib.Path) -> int:
    """Room metadata as small JSON, per-round expectations as packed binary."""
    rooms_dir = root / "test/fixtures/vectors/rooms"
    rounds_dir = root / "test/fixtures/vectors/rounds"
    rooms_dir.mkdir(parents=True, exist_ok=True)
    rounds_dir.mkdir(parents=True, exist_ok=True)

    total = 0
    for name in FAMILIES:
        source = root / f"reference/croom-core/vectors/{name}.json"
        data = json.loads(source.read_text())
        if data.get("format") != "croom-vectors/1":
            print(f"unexpected format in {name}: {data.get('format')!r}", file=sys.stderr)
            return -1

        spec = data["spec"]
        # Kept as a small JSON: it is under a kilobyte, so Foundry parses it instantly, and
        # staying readable matters more than bytes for the handful of fields in a spec.
        (rooms_dir / f"{name}.json").write_text(json.dumps({
            "roomId": "0x" + data["room_id"],
            "encoded": "0x" + spec["encoded_hex"],
            "family": spec["family"],
            "beacon": spec["beacon"],
            "subTicks": spec["sub_ticks"],
            "epochRounds": spec["epoch_rounds"],
            "genesisRound": str(spec["genesis_round"]),
            "initialPrice": spec["initial_price"],
            "decimals": spec["decimals"],
            "mathVersion": spec["math_version"],
            "hashFn": spec["hash_fn"],
            "param": str(next(iter(spec["params"].values()))),
            "initialStateHash": "0x" + data["initial_state"]["hash"],
            "initialLo": data["initial_state"]["lo"],
            "initialHi": data["initial_state"]["hi"],
            "initialLevel": data["initial_state"]["level"],
        }, indent=2) + "\n")

        blob = pack_rounds(data["rounds"])
        (rounds_dir / f"{name}.bin").write_bytes(blob)
        print(f"{name:14s} {len(data['rounds']):>5} rounds  {len(blob):>8} bytes  "
              f"spec {len(spec['encoded_hex']) // 2} bytes")
        total += len(data["rounds"])
    return total


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
    print(f"{'total':14s} {total:>5} maths cases")

    rounds = pack_families(root)
    if rounds < 0:
        return 1
    print(f"{'total':14s} {rounds:>5} rounds")
    return 0


if __name__ == "__main__":
    sys.exit(main())
