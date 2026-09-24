# 0001 — Entropy design

**Decided 2026-09-24**, before step 2.3 was written. Four questions, three answered, one blocked.

## 1. The chain keeps only the floor. Beacon output is proven on demand.

`Entropy` stores **one number**: the highest round for which a valid signature has been shown.
Nothing else. When the ladder narrows a dispute to a single tick, whoever triggers the terminal step
supplies that round's signature and pays ~620,772 gas to have it verified on the spot.

Rejected: a ring buffer of recent outputs (cheap to maintain at 100 gas a slot, but a second code
path through the fraud proof for no benefit the design needs), and storing every proven round
(17,000 gas per round forever, on state that full nodes do not serve anyway).

This keeps `Entropy` honest to the project's central claim: the chain holds commitments and proofs,
not data. Anyone can recompute the beacon history from the public API without asking us.

**Consequence:** two entry points, not one. Verification for a dispute must work for *any* round,
including rounds far below the floor, so verification is a `view` function with no storage effect.
Advancing the floor is the separate, state-changing call.

## 2. Beacon output — ✅ **resolved 24 Sep, and we had already guessed right**

`R_r = SHA-256(σ_r)` — the SHA-256 of the 64-byte signature. Confirmed by
`reference/croom-core/docs/core-v1.md` §2 and by protocol spec v1.1 §5.1.

This was recorded as blocked because the specification was believed not to exist. It does:
`reference/croom-core` is a complete Rust implementation with a bit-exact normative document and
frozen vectors. `Entropy` needs no change — the value it was already going to return is the right
one.

Note the asymmetry worth remembering: **`R_r` is SHA-256, everything downstream is Keccak.** The one
place the other hash function appears.

## 3. We run the floor bot, unrewarded

No treasury, no payout path, no rake plumbing inside `Entropy`. A bot we fund keeps the floor fresh
through the demo and the judging window, at ~0.065 MON per advance.

This is a **scope decision, not a protocol limitation** — a distinction that matters now that the
protocol document is in hand. Spec v1.1 §9.1 already funds this: 10% of rake goes to
"settler / poster / challenger rewards". The incentive exists in the design; we are declining to
build the fee router inside a 20-day window, which is a different statement from "the problem is
unsolved", and the writeup should make exactly that distinction.

Rejected also: making the user who closes market entry pay for the proof. Correct economically,
miserable in a demo, and it puts a 620,772-gas cost on an ordinary action.

## 4. evmnet is hardcoded

Chain hash, public key, DST and period are constants in the contract. There is no beacon parameter,
so there is no field an admin could repoint and no cold storage read on the hot path. Immutability
is structural rather than promised — the same argument `Registry` makes for Room specs.

A second beacon, if it ever happens, is a second deployment. Note that quicknet is BLS12-381 on a
different curve entirely, so a "general" beacon parameter would have been partly illusory anyway.

## What this fixes in the code

| | |
| --- | --- |
| Storage | one slot, `uint64 provenFloor` |
| `verifyRound(round, signature)` | `view`, any round, no state, used by the fraud proof |
| `proveRound(round, signature)` | permissionless, reverts unless it advances the floor |
| Point validation | `isValidPointG1` **before** `0x08` — a junk signature must be an ordinary revert, never a full-limit burn (`docs/audits/bls-solidity.md`) |
| DST | `EvmnetRegistry`'s constant, never `BN254SignatureScheme`'s chain-id-derived one |
| Timestamps | none, anywhere. `block.timestamp` cannot distinguish adjacent blocks on Monad (`docs/monad-facts.md` §7) |
| Admin surface | none. No owner, no pause, no upgrade |
