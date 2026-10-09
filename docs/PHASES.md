# Croom on Monad — execution breakdown

Derived from [PLAN.md](PLAN.md). The plan says *what and why*; this says *what to do next, and what
"done" means*. 12 phases, 61 steps, one commit per step.

- **Start:** 23 Sep 2026 · **Submit:** morning of 13 Oct 2026 · **20 days**
- **Gates:** three. A gate is a demonstrable fact, not a percentage. Do not enter the next phase until the current gate is true.

---

## Commit discipline

**One step = one commit.** Not one per day, not one per file, not one big "week 1" commit. The step
list below *is* the commit log we intend to end up with.

**Message format:** `type(scope): summary`

- Types: `feat` `fix` `test` `bench` `perf` `refactor` `docs` `chore` `ci`
- Scopes: `ops` `entropy` `tick` `registry` `ladder` `market` `web` `indexer`
- Summary in the imperative, lowercase, no trailing period.

**Every commit must leave `forge test` green**, with one deliberate exception: a red-first TDD step
is committed as `test(scope): ... (failing)` and the very next commit turns it green. Phase 6 uses
this on purpose.

**Rules that keep the log worth having**

1. Measured numbers (gas, timings, costs) get committed into `bench/` as files. Numbers that live only in terminal scrollback do not exist when the writeup gets written on day 19.
2. Every testnet deployment commits its address and tx hash into `deployments/`. The README's address table is generated from those files, never hand-typed.
3. Anything fetched from a live source (drand chain info, a beacon round, a Monad doc figure) is committed as a fixture *with its retrieval date*. We verify, then pin — we never trust a number we typed from memory.
4. Gates are annotated tags: `gate-1`, `gate-2`, `gate-3`, `submission`. `git tag -a gate-1 -m "<the fact that is now true>"`.
5. No secrets, ever — deployer keys come from `.env` (gitignored) or a keystore. A committed key means rotating on a deadline.

---

## Phase 0 — Bootstrap · Day 0 (today)

Cheap, and everything else assumes it.

| # | Step | Done when | Commit |
| --- | --- | --- | --- |
| 0.1 | Repo, `.gitignore`, README skeleton | `git log` is non-empty | `chore(ops): initialize repository` ✅ |
| 0.2 | Source plan into the repo | Plan is versioned, not in a chat window | `docs: add source build plan` ✅ |
| 0.3 | This breakdown | Steps and gates are written down before any code | `docs: add phased execution breakdown` ✅ |
| 0.4 | Install Foundry; `forge init` layout; pin the toolchain version in `foundry.toml` and `.tool-versions`; solc pinned exactly | `forge build` succeeds on a pinned version | `chore(ops): foundry scaffold with pinned toolchain` ✅ |
| 0.5 | CI: `forge fmt --check`, `forge build --sizes`, `forge test` on every push | A push runs the suite | `ci(ops): build, fmt and test on push` ✅ |
| 0.6 | `.env.example`, RPC/key handling, deployer policy note | A new machine can be set up from the README alone | `chore(ops): env template and key policy` ✅ |

---

## Phase 1 — Monad ground truth · Day 1

> The highest-risk work in the plan, and the cheapest to fail at. Nothing here is written from
> memory — every figure is measured or fetched today.

| # | Step | Done when | Commit |
| --- | --- | --- | --- |
| 1.1 | Read Developer Essentials → differences, precompiles, network information, RPC differences. Write `docs/monad-facts.md`: chain id, RPC, explorer, faucet, block time, finality, size limits — each with the URL it came from and the date | Every figure has a source link | `docs(ops): monad network facts with sources` ✅ |
| 1.2 | Verify those facts against the live network (`eth_chainId`, a block subscription for real block cadence). Correct the doc where reality and docs disagree | Doc matches the RPC's own answers | `docs(ops): reconcile monad facts against live rpc` ✅ |
| 1.3 | Faucet, deployer funded, trivial contract deployed and verified on the explorer | An explorer link exists | `chore(ops): first testnet deployment recorded` ✅ |
| 1.4 | `GasProbe`: call `0x08` with a valid pairing input and with an invalid one; measure on **testnet**, not in a local EVM. Record in `bench/precompiles.md` | **GATE 1a — the pairing gas cost on Monad is a number in the repo** | `bench(ops): measured 0x08 pairing gas on monad testnet` ✅ |
| 1.5 | While the probe is up: `0x01`, `0x06`, `0x07`, `keccak` baseline, cold vs warm SLOAD across a 128-slot page boundary | The gas table has a row for every primitive we will use | `bench(ops): precompile and storage-page gas baselines` ✅ |

> **Phase 1 complete, 23 Sep — all five steps, all gates passed.**
>
> - **Gate 1a:** `0x08` costs `225,000 + 170,000 × k`, exactly as documented, and computes correctly. 565,124 gas for the two-point check drand needs — confirmed by `eth_call` and again against the deployed probe.
> - Storage pages are exactly 128 slots, boundary at multiples of 128. Cold 8,100, warm 100. Writes decompose as `100 + 8,000·page-load + 2,800·page-write + 17,000·new-slot`.
> - **Monad charges `gas_limit`** — verified, not inherited. And `receipt.gasUsed` reports the *billed* figure, so execution cost cannot be profiled from receipts at all.
> - Two probes deployed, recorded in `deployments/10143/`.
>
> Findings: `bench/precompiles.md`, `bench/storage-paging.md`, `bench/fee-model.md`.
>
> Total spend ~0.47 MON, of which 0.29 was padding on two inconclusive fee-model runs — an object
> lesson in the very thing being measured.

**If 1.4 fails** — pairing missing, mispriced beyond affordability, or behaving differently — stop.
Do not start Phase 2. Raise it the same day; there are still 19 days to change course, and there
will not be on day 10.

---

## Phase 2 — Entropy: beacon verification · Day 2 · **GATE 1**

| # | Step | Done when | Commit |
| --- | --- | --- | --- |
| 2.1 | Fetch evmnet `/info` from the drand HTTP API. Confirm chain hash, scheme `bls-bn254-unchained-on-g1`, period, genesis, public key. Commit the raw JSON as a fixture with its retrieval date. Do not hardcode the hash from the plan until this agrees with it | Fixture on disk; plan's hash confirmed or the discrepancy raised | `test(entropy): pin evmnet chain info fetched from drand api` ✅ |
| 2.2 | Vendor `randa-mu/bls-solidity` as a submodule at a pinned commit. Audit-read it and write `docs/audits/bls-solidity.md`: what it assumes, what it does not check, what we must check ourselves | Read notes exist, commit pinned | `chore(entropy): vendor bls-solidity at pinned commit` ✅ |
| 2.3 | `Entropy.sol`: `verifyRound(round, signature)` → hash-to-G1 over the round number alone, pairing check against the G2 public key. Proven-floor storage, monotonic. **No block timestamps anywhere in this contract** | Unit tests green against ≥20 real rounds | `feat(entropy): round verification and proven floor` ✅ |
| 2.4 | Negative tests: wrong round number, malleated signature, point not on curve, point not in subgroup, infinity, zero, a valid signature for a different round replayed | Every rejection path has a named test | `test(entropy): malformed and replayed signature rejection` ✅ |
| 2.5 | Deploy to testnet. Verify a live round on-chain, floor bumps. Record address, tx hash and measured gas | **GATE 1 — a real evmnet round is verified on Monad and the floor moved** | `feat(entropy): testnet deployment verifying live evmnet rounds` ✅ tagged `gate-1` |

---

> **Gate 1 passed, 3 Oct.** drand evmnet round **21,173,055** verified on Monad testnet; the proven
> floor moved from 0 to 21173055. `Entropy` at `0x09A00a27Cac602e777681F3242f4c7eFe989D4a7`, tx
> `0x2ec8d890…`. The emitted randomness reproduces as `sha256` of the signature fetched from the
> public API, so the claim is checkable by a stranger. Billed 700,000 gas (0.0721 MON) against
> 669,285 executed — the gap is the measured-limit margin, not waste.

## Phase 3 — Port the derivation · Days 3–5

> **This phase changed shape on 24 Sep.** It was written as "design and implement a derivation".
> It is not: `reference/croom-core` is a complete, gated Rust implementation with a bit-exact
> normative spec (`docs/core-v1.md`) and **100,000 rounds of frozen conformance vectors**. Phase 3
> is a **port**, measured against an artefact that already exists.
>
> Three families ship on EVM: **Drift (0)**, **Step (1)**, **Spike (4)**. The reference implements
> all eight; the registry here accepts only these three and says so. A Room opened upstream with
> another family simply is not openable on Monad, which is honest and costs nothing.
>
> Porting hazards are collected in [`docs/porting-notes.md`](porting-notes.md) — `i128` bounds,
> floor-versus-truncate, literal association order, sorted Merkle pairs.

| # | Step | Done when | Commit |
| --- | --- | --- | --- |
| 3.1 | Pin `reference/croom-core` as a submodule; point `spec/` at it | The authority is upstream and versioned | `docs(tick): replace the hand-written spec with the pinned reference implementation` ✅ |
| 3.2 | `bin/pack-vectors.py` — convert `vectors/*.json` to packed fixtures for the fast path | Round-trips; the frozen JSON is never modified | `test(tick): packed fixtures converted from the frozen vectors` ✅ |
| 3.3 | `FixedPointMath`: `mul_div`, `mul_wad`, `div_wad`, `div_int`, `isqrt`, `sqrt_wad`, `floorDiv`, and `i128` bounds on every result | `maths.json` cases pass bit-for-bit | `feat(tick): fixed-point core with i128 bounds` ✅ |
| 3.4 | `exp_wad` and `ln_wad` — 20 terms, the `⌊ ⌋` on `k`, the negative-`k` branch | `maths.json` exp/ln cases pass | `feat(tick): exp_wad and ln_wad` ✅ |
| 3.5 | `inv_phi_wad` — Wichura AS241, three branches, the Appendix A coefficient table | `maths.json` Φ⁻¹ cases pass | `feat(tick): inverse normal CDF (AS241)` ✅ |
| 3.6 | Spec encoding and `roomId`; state encoding and `stateHash` | Every vector's `roomId` and initial `stateHash` reproduce | `feat(tick): spec encoding and room identity` |
| 3.7 | Derived constants — `dt`, `sdt`, `σ_t`, `var_half`, and the per-family constants | Match the reference for all ten vector Rooms | `feat(tick): derived constants` ✅ |
| 3.8 | Randomness: `u(R, roomId, j, stream)`, `uniform_wad` | Draws match for every sampled round | `feat(tick): randomness expansion` ✅ |
| 3.9 | **Drift** family | `drift.json` passes bit-for-bit | `feat(tick): drift price model` ✅ |
| 3.10 | **Step** family | `step.json` passes | `feat(tick): step price model` ✅ |
| 3.11 | **Spike** family | `spike_up`, `spike_down`, `spike_down_wide` pass | `feat(tick): spike price model` |
| 3.12 | Merkle — double-hashed leaves, sorted pairs, odd carry, empty root | Roots and proofs match the vectors | `feat(tick): merkle commitment` ✅ |
| 3.13 | Fast conformance suite over the packed fixtures | **GATE 2a — three families bit-exact against the frozen vectors, suite under 5s** | `test(tick): conformance suite passes bit-exact` ✅ |

**No TypeScript derivation is needed.** The reference ships an SDK that already reproduces every
vector bit-for-bit, so the frontend consumes it and the old step "write a TS derivation" is deleted.
The differential test is now genuinely three-way — Rust, TypeScript and Solidity against one frozen
artefact, none of them written to match the others.

> **Gate 2a passed, 3 Oct.** Both families bit-exact against the reference's frozen vectors:
> **20,000 rounds** and **200 epoch roots** with sample proofs, plus 7,253 arithmetic cases. The
> fast suite is **58 tests in 0.6 s**; `CROOM_FULL_VECTORS=1` runs the complete set in 1.2 s.
>
> Three Solidity-specific traps were hit and are recorded in `docs/porting-notes.md`: memory
> structs alias on assignment, so a test that mutates a "copy" silently mutates the original and
> passes; eagerly built assertion messages exhausted the runner's memory because EVM memory never
> frees; and holding the AS241 tables in `int256[8] memory` cost both that memory and real on-chain
> gas in the fraud proof's terminal step.

## Phase 4 — Registry · Days 6–7 · **GATE 2**

| # | Step | Done when | Commit |
| --- | --- | --- | --- |
| 4.1 | Spec encoding and `roomId = keccak256(spec)`. Store the hash; emit the body in an event | Round-trip test: event body re-hashes to the id | `feat(registry): content-addressed room specs` ✅ |
| 4.2 | Immutability proof: no owner, no setter, no pause, no upgrade path. Storage-layout snapshot test that fails if anyone adds mutable state | A test, not a claim in a comment | `test(registry): immutability and absence of admin surface` ✅ |
| 4.3 | Page-aware layout: proven floor, last finalised epoch, open-challenge pointer contiguous inside one 128-slot page. Document the slot map; assert it with a layout test | Gas measurement shows one cold page per checkpoint op | `perf(registry): contiguous hot-state layout for 128-slot pages` |
| 4.4 | Deploy; script opens 50 Rooms spanning every price model | **GATE 2 — 50 Rooms live on testnet, specs provably immutable, derivation bit-exact** | `feat(registry): testnet deployment and room-opening script` → tag `gate-2` |

---

> **Gate 2 passed, 5 Oct.** `Registry` at `0xE583B914CF2d25fc278301b195aB090640b4eECA`, **50
> distinct Rooms live** on Monad testnet across both families and the whole permitted parameter
> range. Specs provably immutable: `creatorOf` is write-once and the id is the content. Room ids in
> `deployments/10143/rooms.txt`. Cost 0.70 MON, of which 0.188 was multiplier padding now corrected.

## Phase 5 — Ladder I: checkpoints · Days 8–10

| # | Step | Done when | Commit |
| --- | --- | --- | --- |
| 5.1 | Merkle commitment over an epoch's ticks plus resulting state. Epoch sizing chosen against the calldata/event budget (no blobs on Monad) | Sizing decision recorded with its arithmetic | `feat(ladder): epoch merkle commitment` ✅ |
| 5.2 | `postCheckpoint` with bond. Challenge window **measured in rounds above the proven floor**, never in seconds | Window cannot be advanced by a timestamp | `feat(ladder): checkpoint posting with round-denominated window` ✅ |
| 5.3 | `finalize` — unchallenged checkpoints settle, callable by anyone, no privileged finalizer | Anyone can finalize; tests prove it | `feat(ladder): unattended finalization` ✅ |
| 5.4 | Poster bot (TS): gas limits from `bench/`, never padded; balance-headroom alarm; `included` and `executed` as separate states because Monad charges on `gas_limit` and executes asynchronously | Bot survives an induced under-funding without losing its place | `feat(ops): poster bot with measured gas limits and reserve monitoring` |
| 5.5 | Multi-hour unattended run on testnet; log committed | **GATE 2b — checkpoints finalize unattended over hours, with no human at the keyboard** | `chore(ops): multi-hour unattended checkpoint run log` |

---

## Phase 6 — Ladder II: the fraud proof · Days 11–13

> The one thing that never gets cut. **Tests first, deliberately red** — "done" is defined by a
> failing test turning green, so the definition cannot drift under deadline pressure.

| # | Step | Done when | Commit |
| --- | --- | --- | --- |
| 6.1 | Write the adversarial suite *before* the game: liar at the first tick, the last tick, the middle; random epoch sizes; poster who abandons the game; challenger who abandons; challenger at minimum stake; two challengers; griefing poster | Suite compiles and fails for the right reasons | `test(ladder): adversarial fraud-proof suite (failing)` ✅ |
| 6.2 | Single-step challenge and terminal resolve via `Tick`. **This alone is the day-13 cut-line fallback** — build it first so the fallback exists from day 11 | Suite's single-step cases pass | `feat(ladder): single-step challenge and terminal resolve` ✅ |
| 6.3 | Bisection: logarithmic narrowing to one disputed tick, with per-move deadlines in rounds | Narrowing terminates for any epoch size | `feat(ladder): bisection to a single disputed tick` |
| 6.4 | Bond settlement: the winner takes it, timeouts resolve against whoever went silent | No path leaves a bond stranded | `feat(ladder): bond settlement and timeout resolution` ✅ |
| 6.5 | Invariant fuzz: *a dishonest poster with any strategy loses to one honest challenger* | Invariant holds at high `runs`; terminal-step gas is affordable at the intended bond size | `test(ladder): invariant — dishonest poster loses to one honest challenger` ✅ |
| 6.6 | **Live on testnet:** post a knowingly dishonest checkpoint, challenge it, defeat it, take the bond. Commit every tx hash | **GATE 3 — the liar lost their bond on a public chain, and we can link to it** | `feat(ladder): live testnet fraud proof with recorded tx hashes` → tag `gate-3` |

**Cut line, end of day 13:** if 6.3–6.4 are not green, ship 6.2 and stop. Write the bisection design
into the writeup as a stated known limitation. A clear limitation beats a vague claim.

---

> **Gate 3 passed, 9 Oct.** `Ladder` at `0x1bE27643FF478ef280a903831F0927ef68f4374c`. A dishonest
> checkpoint was posted (`0xf8d67a3e…`) and disproved (`0x3b41ce34…`) on Monad testnet; status is
> `Rejected`, the bond was forfeited, and the Room did not advance. The lie was one unit of price.
>
> **No bisection, and no challenger bond** — not a cut-down version but a different and sounder
> shape for this problem. A correct epoch is one where each leaf follows from the last, so naming
> a failure is a *complete* disproof; bisection is only needed when a challenger cannot compute the
> truth, and here they can. See the contract docs on `Ladder`.
>
> The live run had the same address on both sides. `make demo-post-lie` and `make demo-disprove`
> now split it across two accounts for the submission video, because two unrelated addresses are
> part of what the demonstration shows.

## Phase 7 — Conformance sweep and gas table · Day 14

| # | Step | Done when | Commit |
| --- | --- | --- | --- |
| 7.1 | Stream the *complete* vector set through the deployed library, comparing every field | Full sweep green against the deployed bytecode, not just local | `test(tick): full vector sweep against deployed library` |
| 7.2 | Gas table for every entry point, measured on Monad, committed to `bench/gas-table.md` | Every public function has a measured row | `bench(ops): gas table for all entry points` |
| 7.3 | Nightly CI: full sweep plus long-running fuzz | Nightly is green and visible | `ci(ops): nightly full conformance sweep` |
| 7.4 | Re-derive every bot gas limit from 7.2 | No padded limits anywhere — we pay on `gas_limit` | `fix(ops): tighten bot gas limits to measured values` |

---

## Phase 8 — Market · Days 15–16

| # | Step | Done when | Commit |
| --- | --- | --- | --- |
| 8.1 | Parimutuel pool accounting: stake on direction or bucket for round `r` | Payout arithmetic exact, dust accounted, no mint | `feat(market): parimutuel pool accounting` |
| 8.2 | Entry lock at a fixed offset above the proven floor, so no entry is possible once the round's output could exist | Late-entry test cannot be made to pass | `feat(market): entry lock keyed to proven floor` |
| 8.3 | Resolution against the finalised ladder state; claims | Claims settle from a finalised epoch only | `feat(market): resolution and claims` |
| 8.4 | Rake: single fee, stated plainly, no treasury, no admin withdrawal | Rake is a constant with a test asserting it is the only outflow | `feat(market): disclosed rake with no privileged withdrawal` |
| 8.5 | Edge cases: zero-side pool, single staker, dust, reentrancy, claim after challenge overturns an epoch | Every case has a named test | `test(market): payout edge cases and reentrancy` |
| 8.6 | Deploy; record address and gas | Live, addresses committed | `feat(market): testnet deployment` |

**Cut line, end of day 16:** if Market is not green, drop it and submit as verifiable market
infrastructure. The chart anyone can recompute is the stronger demo.

---

## Phase 9 — Client · Day 17

| # | Step | Done when | Commit |
| --- | --- | --- | --- |
| 9.1 | App shell, wallet onboarding via Privy **or** Dynamic (pick one — bounty) | Connect works on Monad testnet | `feat(web): app shell with wallet onboarding` |
| 9.2 | Chart derived in-browser from the beacon, **zero RPC calls** on the derivation path | Network panel shows drand only | `feat(web): chart derived in-browser from the beacon` |
| 9.3 | Room browser over registry events | Rooms from Phase 4 are all browsable | `feat(web): room browser` |
| 9.4 | "Verify against chain" toggle — derivation on one side, committed state on the other, agreement shown explicitly | Toggle shows agreement, and shows disagreement when fed a bad epoch | `feat(web): chain-agreement verification toggle` |
| 9.5 | Offline mode: pre-fetched beacon rounds replay the full history with the network disconnected — this is the demo's third beat | Airplane mode renders the chart | `feat(web): offline re-derivation mode` |
| 9.6 | Market entry UI with the rake disclosed on the face of it (skip if 8.x was cut) | Stake and claim work end to end | `feat(web): market entry and claim` |

---

## Phase 10 — Indexer · Day 18

| # | Step | Done when | Commit |
| --- | --- | --- | --- |
| 10.1 | Envio handlers for room-opened, checkpoint-posted, challenge, resolve, finalize. **Default to finalised blocks** (read RPC Differences first) | Indexer reorg-safe by construction | `feat(indexer): envio handlers for rooms, checkpoints and challenges` |
| 10.2 | Tick and epoch history API — no archival `eth_call`, since full nodes do not serve historical state | Frontend history needs no archive node | `feat(indexer): tick and epoch history api` |
| 10.3 | Wire history into the chart | Long-range history loads | `feat(web): history from indexer` |
| 10.4 | Risk surface: open challenges, bond exposure, epoch lag (Perpl analytics bounty; reuses 9.x) | One page, real numbers | `feat(web): ladder risk surface` |

---

## Phase 11 — Submission · Days 19–20

| # | Step | Done when | Commit |
| --- | --- | --- | --- |
| 11.1 | Freeze on the 12th. Final deploy, all contracts verified, `deployments/` complete | Nothing lands after the freeze | `chore(ops): final testnet deploy and verified addresses` |
| 11.2 | README: address table, gas table, and **the verifiable claim** — a Room ID and a round, with instructions to derive it from the public beacon and confirm it matches the chain | A stranger can reproduce it without asking us anything | `docs: submission readme with verifiable claim` |
| 11.3 | Writeup: what was built inside the window, stated plainly and up front; known limitations (incl. bisection if cut); the P256/passkey sentence; why Monad in the terms of §2 | Honest about provenance before a judge has to discover it | `docs: submission writeup` |
| 11.4 | Demo video, 2–3 min: open a Room → watch it tick → recompute offline → post a dishonest checkpoint → challenge → the liar loses the bond | The last beat is on camera | `docs: demo script and recording notes` |
| 11.5 | Bounty submissions: Envio, wallet, Perpl | Each submitted with its own link | `docs: bounty submission notes` |
| 11.6 | Submit on the **morning of the 13th** | Submitted | `chore(ops): submission freeze` → tag `submission` |

---

## Gate summary

| Tag | The fact that must be true | Day |
| --- | --- | --- |
| `gate-1` | A real drand evmnet round is verified on Monad testnet, the proven floor moved, and the pairing's gas cost is a measured number in `bench/` | 2 |
| `gate-2` | Derivation is bit-exact against sampled vectors, and 50 immutable Rooms are live | 7 |
| `gate-3` | A dishonest checkpoint was posted on public testnet, challenged, and defeated — with tx hashes | 13 |
| `submission` | Frozen, deployed, verified, written up | 20 |

## Cut lines, decided in advance

> **Taken on day 11 — see [`docs/decisions/0002-scope.md`](decisions/0002-scope.md).** Bisection,
> the Envio indexer, a custom frontend, and the Spike family are all cut. Market stays. The fraud
> proof ships single-step and says so.

| Trigger | Cut | Never cut |
| --- | --- | --- |
| Behind at day 13 | Bisection → ship single-step challenge, state it in the writeup | The live fraud proof |
| Behind at day 16 | Market → submit as verifiable market infrastructure | The in-browser re-derivation |
| Behind at day 18 | Indexer polish, risk surface, Kuru | The verifiable claim in the README |

## Open questions — answer before the phase that needs them

| # | Question | Blocks | Needed by |
| --- | --- | --- | --- |
| Q1 | ✅ **Closed 24 Sep — the spec and a full Rust implementation exist**: `reference/croom-core`, pinned at `c1e5b4c`, with `docs/core-v1.md` normative to the bit and 100,000 rounds of frozen vectors. The hand-written spec was deleted. | — | done |
| Q2 | ✅ **Closed — three of the reference's eight families**: Drift (0), Step (1), Spike (4). All three need exact `exp`/`ln`; Drift and Spike need AS241. | — | done |
| Q3 | Privy or Dynamic? | 9.1 | Day 17 |
| Q4 | Bond size, rake %, epoch length, challenge-window length in rounds | 5.2, 6.5, 8.4 | Day 8 |
| Q5 | Where do the poster and challenger bots run for the multi-hour and demo-day windows? | 5.5 | Day 10 |
| Q6 | Is anyone running an honest challenger during judging, or is the demo the only adversarial run? | 6.6, 11.4 | Day 13 |

**Q1 is the sharpest.** Phase 3 has no authority to be bit-exact *against* until it is answered, and
Phases 4–8 all sit behind Phase 3.
