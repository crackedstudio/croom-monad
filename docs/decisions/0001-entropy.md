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

## 2. What counts as "the beacon output" — **BLOCKED**

The answer is "whatever the existing Croom spec says", and the spec is not in this repository.
This is open question **Q1** in `docs/PHASES.md`, and it blocks Phase 3 outright.

It does **not** block step 2.3, provided the choice stays isolated. `Entropy` therefore:

- verifies the signature and returns the **verified 64-byte signature point**, which is the raw fact,
- and exposes `randomness()` as `sha256(signature)`, drand's own canonical definition and the one `EvmnetRegistry` uses.

Whichever the spec names, the derivation layer binds to it at a single boundary, and no part of
`Entropy` has to change. Until the spec is in hand, **nothing downstream may assume which one is
canonical** — and the moment it arrives, a conformance test pins it.

## 3. We run the floor bot, unrewarded

No treasury, no payout path, no rake plumbing inside `Entropy`. A bot we fund keeps the floor fresh
through the demo and the judging window, at ~0.065 MON per advance.

This is a **stated limitation, not an oversight**: in production, floor advancement needs a real
incentive, and the writeup says so plainly rather than implying the problem is solved. The
alternative — funding the prover from the market rake — would have grown `Entropy` a treasury and a
payout surface during week 2, which is where the schedule has no slack.

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
