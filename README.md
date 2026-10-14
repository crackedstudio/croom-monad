# Croom on Monad

**Markets that cannot be rigged by anyone, including the person who created them.**

Every Room is an immutable price process derived from the [drand](https://drand.love) public
randomness beacon. Nobody — not the Room's creator, not us, not validators — can influence a tick
or see it before it exists. Anyone can recompute the entire history from public data, and the chain
is used only to check agreement.

**Live: [croom.crackedstudios.xyz](https://croom.crackedstudios.xyz)** — try to rig a price yourself; no wallet, nothing to install.

Monad Metropolis, Track 01 — Onchain Finance & Trading.

---

## Verify it yourself

Nothing below asks you to trust us. Round **21,173,055** was proven on Monad, and the contract
emitted this randomness:

```
0x0a53345742bad1bdfc2064519f95dfe41bd3044ca9f64d8ed4cbef0c27a6f3e4
```

Check it against the public beacon, without touching our deployment:

```bash
curl -s https://api.drand.sh/v2/chains/04f1e9062b8a81f848fded9c12306733282b2727ecced50032187751166ec8c3/rounds/21173055 \
  | python3 -c 'import sys,json,hashlib; print(hashlib.sha256(bytes.fromhex(json.load(sys.stdin)["signature"])).hexdigest())'
```

Transaction: [`0x2ec8d890…`](https://testnet.monadscan.com/tx/0x2ec8d890c8ead75058d034d7537574b9c26335016215b91db464385988621c93)

The chain holds nothing you have to believe, only something you can check.

---

## A liar lost their bond on this chain

A checkpoint was posted whose price at one round was wrong by **a single unit — 10⁻¹⁸ of a price**,
the smallest lie the encoding can express. It was disproved and the bond forfeited.

| | |
| --- | --- |
| Dishonest checkpoint, by [`0xc50f1F…6179e8`](https://testnet.monadscan.com/address/0xc50f1FbD1c36a2305B257376eb2264C3bB6179e8) | [`0xfbdb3101…`](https://testnet.monadscan.com/tx/0xfbdb310100786244885e913ce66aedbb591ea802ba587f5c03b6b17e3f947027) |
| Disproved by [`0x2E355b…34dEE4`](https://testnet.monadscan.com/address/0x2E355b544488a68f1A9dec41Ffc4e77ac334dEE4), bond forfeited | [`0x35b60b28…`](https://testnet.monadscan.com/tx/0x35b60b28ae9480a74b364f57ae80b975911f99d7cc1731dd7410a21a8bd713cf) |
| Result | status `Rejected` · bond `0` · the Room did not advance |

**Two unrelated addresses, and nothing passed between them.** The watcher re-derived the epoch from
the public beacon, found the leaf that does not follow, and proved it — holding no privilege, no
shared secret and no prior arrangement with the poster. Its balance moved by exactly
`0.2 funded − 0.085 gas + 0.05 bond`.

A lie of one unit is caught as decisively as a large one, because the contract asks whether the
committed value **equals** the re-executed one, not whether it is close. Every rounding rule in the
specification exists for that sentence.

**The challenger posted no bond.** See [Why there is no bisection](#why-there-is-no-bisection).

---

## And a bettor was paid from a proven price

A complete parimutuel round, settled against the ladder rather than against anybody's word.

| | |
| --- | --- |
| Epoch finalised | [`0x9a768b0f…`](https://testnet.monadscan.com/tx/0x9a768b0f9c8fa8048c9e4a8af320e1343f2b665ef4834b924bd923c6ddd8ec3a) |
| Two accounts stake opposite sides | 0.03 DOWN · [0.02 UP](https://testnet.monadscan.com/tx/0x6affba3c91bee7ac1e40b313e5a1eba94f19db58091dafa3a593c3f51b3c60d9) |
| Settled against two proven prices | [`0xb747af55…`](https://testnet.monadscan.com/tx/0xb747af552590e928d1b888031eac6326a3095ff738e9777cef393cfd735d5c92) |
| Winner paid | [`0x533c173d…`](https://testnet.monadscan.com/tx/0x533c173dfdb8bf33aa4e69d835e05d6f1babeb17e9130bbd74487df2c0309407) · staked 0.02, received **0.0495** |

Nothing told the contract a price. It was **shown** two — the open and the close of the window —
each with a Merkle path proving the value belongs to an epoch the ladder had finalised. Pending
checkpoints are refused outright, so a payout can never rest on a commitment the fraud proof might
still overturn.

The 1% rake was credited to the Room's creator rather than sent, because a creator whose address
reverts on receipt must not be able to freeze everybody else's settlement.

---

## Deployed on Monad testnet

Chain `10143`. Generated from [`deployments/`](deployments/10143/), never hand-typed.

| Contract | Address | What it does |
| --- | --- | --- |
| `Entropy` | [`0x09A00a27…89D4a7`](https://testnet.monadscan.com/address/0x09A00a27Cac602e777681F3242f4c7eFe989D4a7) | verifies drand rounds, maintains the proven round floor |
| `Registry` | [`0xE583B914…b4eECA`](https://testnet.monadscan.com/address/0xE583B914CF2d25fc278301b195aB090640b4eECA) | permissionless, content-addressed Room creation |
| `Ladder` | [`0x1fa15283…26025d`](https://testnet.monadscan.com/address/0x1fa152836d8a5E6a0E5db8E2E811089ceE26025d) | epoch commitments and the fraud proof |
| `Market` | [`0xBa0614A0…9d1c9D`](https://testnet.monadscan.com/address/0xBa0614A04243d037A4e05F901eB30C75079d1c9D) | parimutuel rounds, 1% published rake |

**50 Rooms are live**, spanning both shipped price families and the full permitted parameter range —
ids in [`deployments/10143/rooms.txt`](deployments/10143/rooms.txt). Every one has a genesis round
far above the proven floor, so none could have been parameterised against randomness that already
existed.

---

## The frontend proves the claim

```bash
make web && cd web && python3 -m http.server 8173
```

The page derives a Room's chart **in your browser** from the beacon, verifying each BN254 signature
locally, and counts its own RPC calls to Monad while doing it. The counter reads **zero**. Only
afterwards does it ask the chain whether the commitment agrees — and for the Room above it reports
*commitments disagree*, having independently found the same lie the chain rejected.

That ordering is the argument. If Monad were unreachable the chart would still be right.

---

## How it works

```
drand beacon ──→ every 3 seconds, a signed random value nobody can predict
     │
     ├─→ Entropy    verifies a round on chain (one BN254 pairing), raises the proven floor
     ├─→ Registry   roomId = keccak256(spec); the hash is stored, the body is emitted
     ├─→ Tick       (spec, beacon value) → next price. Pure, bit-exact, no storage
     ├─→ Ladder     commits an epoch as one 32-byte root with a bond; anyone can disprove it
     └─→ Market     parimutuel stakes, locked before the deciding randomness exists
```

The chain never stores a price. It stores commitments, and a game that anyone can win if a
commitment is wrong.

### Why there is no bisection

The reference implementation plays a bisection game: challenger and poster halve a disputed range
until they disagree on one round. Bisection exists for games where the challenger **cannot cheaply
compute the truth** and has to search interactively.

That is not this situation. The derivation is deterministic and public, so a challenger running the
reference already knows which round diverges. And a correct epoch is exactly one where the first
leaf follows from the finalised prior state, every leaf follows from the one before it, and the
claimed end state matches the last leaf. **Each is locally checkable in a single transaction** — so
if a root is wrong, at least one fails, and naming it is a *complete* disproof.

Two consequences:

- **The proof is one shot and atomic.** A challenger submits the disproof itself, not a promise to substantiate one later. An invalid disproof simply reverts.
- **The challenger posts no bond.** Bonds on both sides exist to punish stalling in a multi-round game; with no rounds, there is nothing to stall. Watching costs only gas — which is the property the design wants, since safety rests on somebody bothering to look.

### …which only works because posters must publish

That argument has a premise, and it took a second pass to notice: a disproof must exhibit a
committed leaf **with its Merkle path**, and nobody can build a path for a leaf they have never
seen. A poster who committed a bare root and withheld its preimages could not be disproved at all.
A challenger would know the root was wrong and be unable to prove it; the checkpoint would finalise;
and from then on only the poster could produce `provenClose` proofs — which is to say, only the
poster would decide what price settles a market.

This is what bisection provides implicitly: each round of that game forces the poster to disclose a
midpoint. Removing bisection kept the completeness argument and removed the mechanism that made its
premise true.

So `post` takes the leaves themselves and **derives** the root from them, at about 56 bytes of
calldata per round. Three things follow:

| | |
| --- | --- |
| **Data availability** | the preimages are in calldata and in the log, so a disproof is always constructible |
| **Structural validity** | rounds must be exactly the epoch's, contiguous and ascending — a tree holding two leaves for the same round cannot be committed, which matters because sorted-pair Merkle proofs cannot bind a leaf's *position* and both would otherwise verify |
| **Root honesty** | the root cannot disagree with the leaves, because it is computed from them |

With that, the one-shot disproof is a different shape rather than a reduced one.

---

## Three implementations, one frozen specification

| | Language | Role |
| --- | --- | --- |
| [`croom-core`](https://github.com/crackedstudio/croom-core) | Rust | the reference; produced the vectors |
| its SDK | TypeScript | reproduces the vectors; drives this frontend |
| **this repository** | **Solidity** | **reproduces them on Monad** |

The Solidity was written last, against vectors frozen before it existed and which it cannot
influence. It reproduces them exactly:

| | |
| --- | ---: |
| Fixed-point arithmetic cases | 7,253 |
| Derivation rounds, both families | 20,000 |
| Epoch roots with sample proofs | 200 |
| Test suite | 102 tests, 0.6 s |

Bit-exact means bit-exact: the suite asserts *which* error each failing case raises, not only that
it fails.

---

## Measurements

Everything is measured on Monad, never inherited from Ethereum's published costs.

| | |
| --- | --- |
| [`bench/precompiles.md`](bench/precompiles.md) | `ecPairing` is `225,000 + 170,000/point` — **5× Ethereum** |
| [`bench/fee-model.md`](bench/fee-model.md) | Monad charges **`gas_limit`**, verified; and `receipt.gasUsed` reports the *billed* figure, so receipts cannot measure execution |
| [`bench/storage-paging.md`](bench/storage-paging.md) | pages are exactly 128 slots; reuse beats growth **170×** |
| [`bench/gas-estimation.md`](bench/gas-estimation.md) | a tool's estimate is wrong by 1.2–2.4×, and the factor is a property of the *transaction* |
| [`bench/gas-table.md`](bench/gas-table.md) | every entry point |
| [`bench/verify-gas.md`](bench/verify-gas.md) | round verification across 32 real beacon rounds |

The number the architecture rests on: verifying a round costs **~657,000 gas**, of which 97% is one
precompile. At 3-second rounds, verifying every round would cost about **1,600 MON a day** — not
expensive, impossible. That is why the ladder exists.

---

## A finding against the specification

[`docs/findings/0001-floor-freshness.md`](docs/findings/0001-floor-freshness.md)

Both fairness rules compare a target round against the **proven floor**. Spec v1.1 §8.5 says floor
freshness is "an operator concern, not a safety one — a stale floor only pushes entries further into
the future."

We believe that has the inequality backwards. A stale floor is a *low* floor, which makes the
thresholds low and admits **more** rounds — including ones already published. Measured on this
deployment: the floor was **155,015 rounds (129 hours) behind** the beacon, which means our own
Registry would have accepted a Room whose entire history the creator could compute first.

There is a passing test named `test_KnownHazard_AStaleFloorAdmitsStakesOnDecidedRounds` that
demonstrates it rather than hiding it, and the write-up notes the uncomfortable part: the obvious
fix reintroduces the time dependence the proven-floor design was meant to remove.

---

## What was built inside the competition window

Stated plainly, because a judge who discovers it themselves discounts everything else.

**Predates the window.** The protocol specification (dated 13 September 2026), the Rust reference
implementation, its TypeScript SDK, and the frozen conformance vectors — all in
[`reference/croom-core`](reference/croom-core), pinned at commit `c1e5b4c`. That is the second host
chain's worth of prior art, and this submission is the port.

**Built inside the window.** Everything in `src/`, `test/`, `script/`, `bench/`, `docs/` and `web/`:

- the entire Solidity implementation — fixed point, `exp`/`ln`, AS241, the derivation, Merkle, `Entropy`, `Registry`, `Ladder`, `Market`
- 102 tests, including the adversarial suite and the vector conformance harness
- every Monad measurement in `bench/`, and the probe technique behind them
- the frontend's chain layer and the verification view
- the floor-freshness finding

The git history is the evidence: 77 commits, one per step, tagged at each gate.

---

## Known limitations

| | |
| --- | --- |
| **Two of eight families** | Drift and Step ship on EVM. The reference implements all eight; a Room opened upstream with another family is simply not openable here. |
| **No fee router** | The rake goes entirely to the Room's creator. The protocol's four-way split (treasury / creator / jackpot / operations) is not implemented. |
| **Nothing pays for floor advancement** | Which is what makes the finding above live on this deployment rather than theoretical. |
| **No indexer** | Room and epoch history is read from logs. Monad's RPC caps `eth_getLogs` at 100 blocks, so a long backfill pages deliberately. |
| **Nothing runs continuously** | One Room has a committed, finalised epoch and one settled market. No bot posts checkpoints or watches for lies on a schedule, so the other 49 Rooms have no on-chain commitments — which the frontend reports plainly rather than hiding. |

---

## Building

Foundry `1.4.3` and Node `20+`, both pinned — see [`docs/toolchain.md`](docs/toolchain.md).

```bash
git submodule update --init --recursive   # the reference implementation and its vectors
forge build && forge test                 # 112 tests
CROOM_FULL_VECTORS=1 forge test           # the complete 20,000-round sweep
make web                                  # regenerate addresses, build the frontend
```

| | |
| --- | --- |
| [`docs/PHASES.md`](docs/PHASES.md) | the build plan, step by step, with each gate |
| [`math_breakdown.md`](math_breakdown.md) | the mathematics from first principles, assuming only algebra |
| [`docs/porting-notes.md`](docs/porting-notes.md) | what Solidity makes harder than Rust |
| [`spec/`](spec/) | pointer to the normative specification upstream |

## What is where

| | |
| --- | --- |
| [`src/`](src/) | the four contracts, plus the fixed-point and Merkle libraries they share |
| [`test/`](test/) | 112 tests, including the frozen vectors the Rust reference produced |
| [`script/`](script/) | deployment and the two live demonstrations, as Foundry scripts |
| [`web/`](web/) | the site: landing page, writing, and the app that derives prices in your browser |
| [`indexer/`](indexer/) | Envio HyperIndex — Rooms, checkpoints, markets and stakes |
| [`bench/`](bench/) | gas measured against a live node, and what we got wrong estimating it |
| [`docs/findings/`](docs/findings/) | a problem we found in the specification and reported rather than patched around |
| [`docs/decisions/`](docs/decisions/) | why the entropy source and the scope are what they are |
| [`deployments/`](deployments/) | addresses and deployment transactions, written by `bin/record-deployment.py` |
| [`ad/`](ad/) | the 30-second advert: a real price series, and a soundtrack that pulses with the beacon |
