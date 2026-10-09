# Finding 0001 — floor freshness is a safety property, not an operator convenience

**Found 9 October 2026 during the Monad port.** Concerns the reference protocol specification, not
only this implementation.

## What the specification says

Spec v1.1 §8.5, on the entry buffer:

> **Freshness is an operator concern, not a safety one.** A stale floor only pushes entries further
> into the future, which is safe but worse UX. Keeping it fresh costs roughly one verification per
> minute.

## Why we believe that is backwards

Both fairness rules compare a target round against the **proven floor**:

| Rule | Where | Condition |
| --- | --- | --- |
| A Room's first round must not exist yet | §7.1 / P2 | `genesisRound > provenFloor + B` |
| A stake must be placed before its randomness exists | §8.5 | `provenFloor + B <= startRound` |

A stale floor is a **low** floor. A low floor makes both thresholds low, so **more** rounds
qualify — including rounds that have already been published. The staleness does not push entries
into the future; it pushes the *boundary* into the past.

The quoted reasoning appears to have the inequality the wrong way round.

## It is not theoretical

Measured on our own deployment, 9 October:

| | |
| --- | --- |
| drand evmnet head | 21,328,070 |
| `Entropy.provenFloor()` on Monad | 21,173,055 |
| Behind by | **155,015 rounds — 129 hours** |

Every one of those 155,015 rounds is public, signed, and permanently retrievable from
`api.drand.sh`. With the floor where it was, our own `Registry` would have accepted a Room whose
genesis sits anywhere in that window — a Room whose entire price history the creator could compute
before choosing its parameters. The rule that exists to prevent exactly this passes, because the
rule's reference point is the floor and the floor is five days behind.

`test_KnownHazard_AStaleFloorAdmitsStakesOnDecidedRounds` in `test/Market.t.sol` demonstrates the
market half: a stake is accepted on a window the test has already derived the outcome of.

## Why the floor goes stale by default

Nobody is obliged to advance it, and advancing it costs money — 669,285 gas, about 0.07 MON at
current prices (`bench/gas-estimation.md`). Spec v1.1 §9.1 allocates 10% of rake to
"settler / poster / challenger rewards", but floor advancement is not a settlement, a post or a
challenge, and in our port nothing pays for it at all (`docs/decisions/0001-entropy.md` §3).

An attacker does not need to suppress the floor. They only need it to be behind, which is its
resting state.

## What follows

**For the protocol.** The sentence should be inverted: floor freshness is a precondition of the
fairness guarantee, and the maximum tolerable staleness is a protocol parameter rather than an
operational preference. A conservative framing: a Room may only be opened, and a stake only
accepted, if the floor is within some bounded distance of the chain's own notion of now — which
reintroduces a dependence on time that the proven-floor design was specifically meant to remove.
That tension looks real and we do not think it is resolved by this document.

**For this port.** Two things are true and both are stated in the submission rather than papered
over:

1. `Registry` and `Market` implement the rules as specified, so they inherit the weakness.
2. Nothing here pays anyone to advance the floor, so on this deployment the weakness is live.

A floor-advancing bot funded by us closes it for the demo and the judging window. That is an
operational patch over a design gap, and calling it anything else would be dishonest.

## What we are not claiming

That the beacon is weak, that the fraud proof is affected, or that any funds on this deployment are
at risk — the markets here are testnet and the only staker is us. The claim is narrower: **a rule
written to prevent betting on known outcomes does not prevent it unless something keeps the floor
fresh, and the specification says the opposite.**
