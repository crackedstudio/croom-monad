# Croom on Monad

A permissionless protocol for markets whose price series is generated from public randomness,
deployed on Monad.

Every Room is an immutable price process derived from the drand beacon. Nobody — not the Room's
creator, not the protocol's authors, not validators — can influence a tick or see it before it
exists, and anyone can recompute the entire history from public data with no RPC access at all.

**Markets that cannot be rigged by anyone, including the person who created them — settling every
600 milliseconds on Monad.**

Built for the Monad Metropolis hackathon, Track 01 — Onchain Finance & Trading.

## Setup

Requires Foundry `1.4.3` and Node `20.13.1` — both pinned, see [docs/toolchain.md](docs/toolchain.md).

```bash
git submodule update --init --recursive
cp .env.example .env    # fill in; no private keys go here — see docs/keys.md
forge build && forge test
```

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

Monad testnet (chain `10143`). Generated from `deployments/`, never hand-typed.

| Contract | Address | Purpose |
| --- | --- | --- |
| `GasProbe` | [`0x5222AC024a4D74435f943A889C111DBFe330215B`](https://testnet.monadscan.com/address/0x5222AC024a4D74435f943A889C111DBFe330215B) | measurement scaffolding, step 1.4 |
| `StoragePageProbe` | [`0xc33056Af574168157a7D801Ab213cf1d4416dDc6`](https://testnet.monadscan.com/address/0xc33056Af574168157a7D801Ab213cf1d4416dDc6) | measurement scaffolding, step 1.5 |

Neither is part of the protocol. Measurements: [`bench/`](bench/).
