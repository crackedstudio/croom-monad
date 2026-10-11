#!/usr/bin/env python3
"""Prints a settled market as the chain holds it. Read-only; takes its values from the Makefile.

Separate from the Makefile because `cast --json` returns decimal strings and a shell can neither
divide by 10^18 nor name an enum, and the three attempts at doing it in make all mangled the
positional fields.
"""
import json
import os

STATE = ["none", "open", "settled", "void"]
SIDE = ["up", "down"]


def mon(v: int) -> str:
    """Exactly, from the integer. Dividing by 10**18 in float turns 5*10**16 into 0.050000000000000003."""
    whole, frac = divmod(v, 10**18)
    tail = f"{frac:018d}".rstrip("0")
    return f"{whole}.{tail}" if tail else str(whole)


def main() -> None:
    with open("/tmp/croom-book.json") as fh:
        room, start, end, up, down, pool, state, winner = (int(x, 0) if str(x).startswith("0x") else int(x) for x in json.load(fh))
    rake = int(json.loads(os.environ["RAKE"])[0])
    bal = int(os.environ["BAL"])
    staked = up + down

    print(f'market     {os.environ["M"]}')
    print(f'id         {os.environ["I"]}')
    print(f"room       {hex(room)}")
    print(f"window     rounds {start:,} .. {end:,}  ({end - start + 1} rounds)")
    print()
    print(f"up         {mon(up)} MON")
    print(f"down       {mon(down)} MON")
    print(f"staked     {mon(staked)} MON")
    print(f"pool       {mon(pool)} MON   paid to the winning side")
    print(f"rake       {mon(staked - pool)} MON   {(staked - pool) * 10000 // staked} bps, as published")
    print()
    print(f"state      {state} ({STATE[state]})")
    print(f"winner     {winner} ({SIDE[winner]})")
    print()
    print(f"balance    {mon(bal)} MON held by the contract")
    print(f"rake owed  {mon(rake)} MON to the creator")
    if bal == rake:
        print("           the contract holds exactly the unwithdrawn rake and nothing else")
    elif bal > rake:
        print(f"           {mon(bal - rake)} MON above the rake: a winner has not claimed yet")
    claimed = {k: json.loads(os.environ[k])[0] == "true" for k in ("A", "B")}
    yn = lambda b: "yes" if b else "no"
    print(f'claimed    deployer {yn(claimed["A"])}, challenger {yn(claimed["B"])}')
    print("           a claim by the losing side reverts, which is why one of these stays no")


if __name__ == "__main__":
    main()
