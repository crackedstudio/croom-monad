# spec — pointer, not a specification

**The specification lives in the reference implementation, not here.**

| Document | Where |
| --- | --- |
| Protocol specification v1.1 | [`reference/croom-core/docs/05-croom-protocol-v1.1.md`](../reference/croom-core/docs/05-croom-protocol-v1.1.md) |
| **Croom core v1 — normative, bit-exact definition** | [`reference/croom-core/docs/core-v1.md`](../reference/croom-core/docs/core-v1.md) |
| Rust reference implementation | [`reference/croom-core/crates/croom-core/`](../reference/croom-core/crates/croom-core/) |
| **Frozen conformance vectors** | [`reference/croom-core/vectors/`](../reference/croom-core/vectors/) |

`reference/croom-core` is a submodule pinned at `c1e5b4c`.

## The order of authority

1. **The vectors.** `vectors/` is a frozen public interface. Where `core-v1.md` and the vectors disagree, the vectors win — the document says so itself.
2. **`core-v1.md`**, which pins every operation to the bit: `exp_wad`, `ln_wad`, `inv_phi_wad` (Wichura AS241 with its coefficient table), the randomness expansion, the spec encoding, the Merkle construction.
3. **Protocol spec v1.1**, which defines what the system is for.

Our Solidity is measured against (1). It is a **port**, not a design.

## What happened to the spec that used to be here

On 24 September this directory briefly held a derivation spec written from scratch, on the
understanding that none existed. One does. The hand-written version diverged from it in the
randomness expansion, the price models, the draw distribution and the volatility
parameterisation, and it had no martingale calibration. It was deleted rather than reconciled,
because there is exactly one authority and it is upstream.

Two things from that detour were worth keeping and have moved:

- The truncation and association-order rules, now in [`docs/porting-notes.md`](../docs/porting-notes.md) alongside the Solidity-specific hazards.
- The packed-fixture idea, now a *converter* (`bin/pack-vectors.py`) rather than a competing format. The JSON vectors are 3 MB each and Foundry parses JSON slowly enough to discourage running the suite; packing them for the fast path changes nothing about the frozen artefact.
