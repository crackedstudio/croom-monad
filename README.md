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
| **`Entropy`** | [`0x09A00a27Cac602e777681F3242f4c7eFe989D4a7`](https://testnet.monadscan.com/address/0x09A00a27Cac602e777681F3242f4c7eFe989D4a7) | **beacon verification and the proven round floor** |
| **`Registry`** | [`0xE583B914CF2d25fc278301b195aB090640b4eECA`](https://testnet.monadscan.com/address/0xE583B914CF2d25fc278301b195aB090640b4eECA) | **permissionless, content-addressed Room creation** |
| `GasProbe` | [`0x5222AC024a4D74435f943A889C111DBFe330215B`](https://testnet.monadscan.com/address/0x5222AC024a4D74435f943A889C111DBFe330215B) | measurement scaffolding, step 1.4 |
| `StoragePageProbe` | [`0xc33056Af574168157a7D801Ab213cf1d4416dDc6`](https://testnet.monadscan.com/address/0xc33056Af574168157a7D801Ab213cf1d4416dDc6) | measurement scaffolding, step 1.5 |

**50 Rooms are live**, spanning both families and the full permitted parameter range — all ids in
[`deployments/10143/rooms.txt`](deployments/10143/rooms.txt). Every one has a genesis round far
above the proven floor, so none could have been parameterised against randomness that already
existed.

The two probes are measurement scaffolding, not protocol. Measurements: [`bench/`](bench/).

## Verify it yourself

Round **21,173,055** was proven on Monad in transaction
[`0x2ec8d890…`](https://testnet.monadscan.com/tx/0x2ec8d890c8ead75058d034d7537574b9c26335016215b91db464385988621c93),
and the contract emitted randomness `0x0a53345742bad1bdfc2064519f95dfe41bd3044ca9f64d8ed4cbef0c27a6f3e4`.

Check it against the public beacon, without asking us for anything:

```bash
curl -s https://api.drand.sh/v2/chains/04f1e9062b8a81f848fded9c12306733282b2727ecced50032187751166ec8c3/rounds/21173055 \
  | python3 -c 'import sys,json,hashlib; print(hashlib.sha256(bytes.fromhex(json.load(sys.stdin)["signature"])).hexdigest())'
```

That is the whole claim in miniature: the chain holds nothing you have to trust, only something you
can check.
