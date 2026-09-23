# Croom on Monad

A permissionless protocol for markets whose price series is generated from public randomness,
deployed on Monad.

Every Room is an immutable price process derived from the drand beacon. Nobody — not the Room's
creator, not the protocol's authors, not validators — can influence a tick or see it before it
exists, and anyone can recompute the entire history from public data with no RPC access at all.

**Markets that cannot be rigged by anyone, including the person who created them — settling every
600 milliseconds on Monad.**

Built for the Monad Metropolis hackathon, Track 01 — Onchain Finance & Trading.

## Status

Pre-build. See [docs/PHASES.md](docs/PHASES.md) for the execution breakdown and
[docs/PLAN.md](docs/PLAN.md) for the strategy document it derives from.

## Components

| Component  | What it is                                                            |
| ---------- | --------------------------------------------------------------------- |
| `Entropy`  | drand evmnet verification (BN254 pairing) and the proven round floor   |
| `Registry` | permissionless, content-addressed Room specs                          |
| `Tick`     | pure derivation: (spec, round, beacon output) → next price            |
| `Ladder`   | epoch commitments, bisection fraud proofs, bonds                      |
| `Market`   | parimutuel rounds keyed to the proven floor                           |

## Deployments

Addresses land here once Phase 1 deploys. Nothing is live yet.
