# 0002 — Scope, decided day 11

**3 October 2026. Ten days to submission.** Eight days elapsed between 25 September and today with
no work committed, which is the whole of the slack the original plan had.

## Position

| Gate | Due | Actual |
| --- | --- | --- |
| Gate 1 — round verified on chain, floor bumped | Day 2 | crypto proven by `eth_call`; **no contract** |
| Gate 2 — derivation bit-exact, 50 Rooms | Day 7 | maths layer only (7,253 cases pass) |
| Gate 2b — unattended finalization | Day 10 | not started |
| Gate 3 — **fraud proof live** | Day 13 | not started |

Critical path remaining: ~9.5 days against 10 available, with the hard half of Phase 3 behind us —
`exp`, `ln` and AS241 were where a silent divergence could hide, and they are done.

## Decision

**Keep Market. Cut bisection.** The fraud proof ships as a **single-step challenge** and the
writeup states that plainly, with the bisection design described as the work that would replace it.

PLAN.md §5 argues the other way — "the chart anyone can recompute is a stronger demo than a rushed
betting UI" — and the arithmetic agrees, since bisection is ~1 day and Market is ~2. Recorded here
because the decision was taken against that advice, with the judging context in mind, and because a
decision made under pressure should be legible later.

To make it fit, three further cuts were taken at the same time rather than on the days the plan
would have triggered them:

| Cut | Saves | Why it is survivable |
| --- | --- | --- |
| Envio indexer | ~1 day | The chart derives from the beacon; epoch history comes from events directly. Forfeits the $1,000 bounty. |
| Custom frontend | ~1 day | `reference/croom-core/sdk` already derives in-browser with no RPC and renders a chart — the demo's third beat, for free. We point it at Monad and add the chain-agreement toggle. |
| Spike family | ~0.5 day | Ship Step and Drift. Step validates the plumbing without transcendentals; Drift is the default and the one that looks like a market. Spike only if days remain. |

## What this protects

The live fraud proof, in the form PLAN.md insists on: a dishonest checkpoint posted on public
testnet, challenged, and defeated, with transaction hashes in the README. Single-step rather than
bisected, but **live and adversarial**, which is the part nobody else will have.

## Order of work

1. `Entropy` — contract, deploy, **Gate 1**. Unconditional, and cheapest now: the crypto is proven and the library audited.
2. `Tick` — spec encoding, state, derived constants, randomness, Step, Drift, Merkle. **Gate 2a**.
3. `Registry` — 50 Rooms. **Gate 2**.
4. `Ladder` — post, finalize, single-step challenge, adversarial suite, live defeat. **Gate 3**.
5. `Market` — parimutuel round, entry lock above the floor, claim.
6. Frontend from the reference SDK, plus the chain-agreement toggle.
7. Submission: final deploy, README with the verifiable claim, gas table, video, freeze.

## The honest line for the writeup

Three implementations of one frozen specification — Rust, TypeScript and Solidity — agreeing
bit-for-bit, with the Solidity written last against vectors it cannot influence. The fraud proof is
single-step by deliberate choice under a deadline, not by oversight, and the design that replaces it
is written down.
