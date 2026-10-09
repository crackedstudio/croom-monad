# Croom on Monad

**Markets that cannot be rigged by anyone, including the person who created them.**

Every Room is an immutable price process derived from the [drand](https://drand.love) public
randomness beacon. Nobody — not the Room's creator, not us, not validators — can influence a tick
or see it before it exists. Anyone can recompute the entire history from public data, and the chain
is used only to check agreement.

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
| Dishonest checkpoint | [`0xf8d67a3e…`](https://testnet.monadscan.com/tx/0xf8d67a3e6fb1e739c3d017bc58f4d2f8584bd00b3a6944c34b0e5d3422c69cb0) · 413,067 gas |
| Disproved, bond forfeited | [`0x3b41ce34…`](https://testnet.monadscan.com/tx/0x3b41ce3409f4af0ddeaaaa517b087da3d771a764a033d97d99085c45d05f12b5) · 817,530 gas |
| Result | status `Rejected` · bond `0` · the Room did not advance |

A lie of one unit is caught as decisively as a large one, because the contract asks whether the
committed value **equals** the re-executed one, not whether it is close. Every rounding rule in the
specification exists for that sentence.

**The challenger posted no bond.** See [Why there is no bisection](#why-there-is-no-bisection).

---

## Deployed on Monad testnet

Chain `10143`. Generated from [`deployments/`](deployments/10143/), never hand-typed.

| Contract | Address | What it does |
| --- | --- | --- |
| `Entropy` | [`0x09A00a27…89D4a7`](https://testnet.monadscan.com/address/0x09A00a27Cac602e777681F3242f4c7eFe989D4a7) | verifies drand rounds, maintains the proven round floor |
| `Registry` | [`0xE583B914…b4eECA`](https://testnet.monadscan.com/address/0xE583B914CF2d25fc278301b195aB090640b4eECA) | permissionless, content-addressed Room creation |
| `Ladder` | [`0x1bE27643…f4374c`](https://testnet.monadscan.com/address/0x1bE27643FF478ef280a903831F0927ef68f4374c) | epoch commitments and the fraud proof |
| `Market` | [`0xB0988209…6805a7`](https://testnet.monadscan.com/address/0xB0988209C76941023bD7D6d9Fba45773636805a7) | parimutuel rounds, 1% published rake |

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

This is a different shape, not a reduced one.

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
| **The live fraud proof ran from one address** | Poster and challenger were the same key. `make demo-post-lie` and `make demo-disprove` split it across two accounts; the recorded run did not use them. |

---

## Building

Foundry `1.4.3` and Node `20+`, both pinned — see [`docs/toolchain.md`](docs/toolchain.md).

```bash
git submodule update --init --recursive   # the reference implementation and its vectors
forge build && forge test                 # 102 tests
CROOM_FULL_VECTORS=1 forge test           # the complete 20,000-round sweep
make web                                  # regenerate addresses, build the frontend
```

| | |
| --- | --- |
| [`docs/PHASES.md`](docs/PHASES.md) | the build plan, step by step, with each gate |
| [`math_breakdown.md`](math_breakdown.md) | the mathematics from first principles, assuming only algebra |
| [`docs/porting-notes.md`](docs/porting-notes.md) | what Solidity makes harder than Rust |
| [`spec/`](spec/) | pointer to the normative specification upstream |
