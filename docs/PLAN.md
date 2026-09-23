# Croom on Monad — Metropolis build plan

> Source strategy document. This is the *why*. The *how and when* is [PHASES.md](PHASES.md).

**Target:** Monad Metropolis global hackathon, Track 01 — Onchain Finance & Trading
**Window:** 1 Sep – 13 Oct 2026 · **We start:** 23 Sep · **20 days**
**Judging:** 14–27 Oct · **Winners:** 3 Nov
**Prizes:** $30,000 per track split between 3 teams · $25,000 grand champion · $250,000+ total with sponsor bounties

## 1. What we are submitting

A permissionless protocol for markets whose price series is generated from public randomness,
deployed on Monad. Every Room is an immutable price process derived from the drand beacon. Nobody —
not the Room's creator, not the protocol's authors, not validators — can influence a tick or see it
before it exists, and anyone can recompute the entire history from public data with no RPC access at
all.

The submission is three things:

- **Contracts on Monad** — beacon verification, Room registry, commitment ladder with fraud proofs, and a parimutuel round market.
- **A client that proves the claim** — a chart that renders a Room's full history from the beacon alone, in the browser, with the chain used only to check agreement.
- **A live adversarial demo** — a dishonest checkpoint posted on-chain, challenged, and provably defeated, in front of the judge.

**The one-line pitch:** Markets that cannot be rigged by anyone, including the person who created
them — settling every 600 milliseconds on Monad.

## 2. Why Monad, in judge-facing terms

Track 01's own framing is "fast settlement makes new financial instruments and fully onchain markets
more practical," with "perpetuals with funding that updates every block" as a worked example. The
argument to make:

- **The instrument requires sub-second finality to exist.** The beacon emits a round every 3 seconds. A market round must open, lock, resolve and pay inside that window. Monad finalises deterministically in 600ms at 300ms block times, so a full settlement cycle fits inside a single tick with margin. On a 12-second chain this instrument is not slow — it is impossible.
- **The cryptography is native here.** Beacon verification is a BN254 pairing check. Monad supports the full Ethereum precompile set including `0x08`, repriced for its execution environment, so verification is a precompile call rather than a hand-rolled circuit.
- **Fraud proofs need cheap terminal steps.** A bisection game is only credible if the final single-step re-execution is affordable to submit. High throughput and low fees are what make an honest challenger economically viable at small stake sizes.

Do not claim Monad is the only chain this runs on. Claim that the market cadence is what the chain
unlocks, and demonstrate it.

## 3. Architecture

Five components. Solidity, Foundry.

### 3.1 Entropy — beacon verification

Verifies drand evmnet rounds and maintains a **proven round floor**: the highest round for which a
valid signature has been shown on-chain.

- Beacon: League of Entropy evmnet, scheme `bls-bn254-unchained-on-g1`, 3-second period, public keys on G2 and short signatures on G1.
- Chain hash: `04f1e9062b8a81f848fded9c12306733282b2727ecced50032187751166ec8c3` — confirm against the drand HTTP API at build time rather than trusting any single written source.
- **Unchained scheme:** the signed message is the round number alone, so a round can be verified in isolation without a chain of predecessors. This is what makes spot verification cheap.
- Use `randa-mu/bls-solidity` for hash-to-G1 and the pairing check rather than writing a verifier. Audit-read it, pin the commit, and write our own conformance tests against live rounds.
- **Never bind rounds to block timestamps.** The floor is a proof that a round exists; a timestamp is an estimate of when it existed. Entry buffers and market locks key off the floor only.

### 3.2 Registry — permissionless Room creation

- A Room is opened by submitting an immutable spec. `roomId = keccak256(spec)`.
- Store the hash, not the body. Emit the full spec in an event for indexers to pick up. Immutability is then structural: there is no field an admin could change, because the identifier is the content.
- No owner, no pause on existing Rooms, no upgrade path that can touch a live spec.

### 3.3 Tick — the derivation library

The deterministic map from `(spec, round, beacon output)` to the next price. Pure, view-only, no
storage.

- Keccak-256 throughout. It is a native EVM opcode, so the hash layer costs us nothing to move.
- 18-decimal fixed point on `int256`, truncating toward zero. Solidity's `/` already has the required rounding semantics, so a correct implementation inherits correct rounding from the language rather than from a helper we might get wrong.
- No floating point anywhere, including in tests and in the indexer.
- This library is the conformance surface. Everything in §6 exists to prove it is bit-exact.

### 3.4 Ladder — commitment and fraud proofs

The chain does not store prices. It stores commitments to batches of ticks, and a game that anyone
can win if a commitment is wrong.

- **Post:** a checkpoint commits an epoch of rounds — a Merkle root over the ticks plus the resulting state — with a bond.
- **Challenge window:** measured in rounds above the proven floor, not in seconds.
- **Bisection:** challenger and poster narrow their disagreement to a single tick over a logarithmic number of moves.
- **Resolve:** the contract executes that one tick via `Tick` and pays the bond to whoever was right.
- **Finalize:** unchallenged checkpoints settle automatically after the window.

Design target: the dishonest poster always loses, at any epoch size, against a single honest
challenger with no special privileges.

### 3.5 Market — parimutuel rounds

- Stake on a direction or bucket for round `r`; the pool splits among the correct side, less rake.
- Entry closes at a fixed offset above the proven floor so that no entry can be made once the round's beacon output could exist.
- No treasury, no LP to drain, no mint. Rake is the only fee and it is stated plainly in the interface, not buried.

## 4. Monad-specific engineering constraints

These are the things that bite, taken from Developer Essentials. Read that page in full before
writing the first contract.

| Constraint | What it changes for us |
| --- | --- |
| Fees are charged on `gas_limit`, not `gas_used` — the sender pays `value + gas_bid × gas_limit` | The single biggest behavioural difference. Every automated poster and challenger must set a tight, measured gas limit. A challenge that succeeds cheaply still costs the full limit. Bonds must be sized against the worst-case limit, not against expected consumption. Benchmark first, then set limits from measurements. |
| Reserve balance / asynchronous execution — transactions can be consensus-included but revert at execution if funds are short | Poster and challenger bots need balance headroom monitoring, not just a nonce manager. Treat "included" and "executed" as separate states in the bot's state machine. |
| Storage is paged in 128-slot pages — first touch of a page pays cold, the rest of the page is warm for the transaction | Lay out each Room's hot state (proven floor, last finalised epoch, open challenge pointer) contiguously so one cold page covers a whole checkpoint operation. Do not scatter a checkpoint across mapping slots that hash to different pages. |
| 128 KB max contract size, 256 KB init code | We can ship the derivation library, verifier and ladder without splitting into proxy/diamond gymnastics. Prefer one well-tested contract over a clever modular one. |
| Precompiles `0x01`, `0x06`–`0x0a` are repriced relative to Ethereum | Do not budget the pairing from Ethereum's published cost. Measure `0x08` on testnet on day one and build the gas table from that number. |
| Blob transactions (EIP-4844, type 3) are not supported | Epoch data goes in calldata or an event, not a blob. Size epochs accordingly. |
| Full nodes do not serve arbitrary historical state | The frontend must not depend on archival `eth_call` at old blocks. History comes from the indexer or from re-derivation off the beacon — which we can do anyway, and that is the whole point. |
| Extra precompiles available — BLS12-381 (EIP-2537) and P256 (`0x0100`, EIP-7951) | P256 is a free win if we want passkey-signed market entries later. Out of scope for the deadline; worth one sentence in the writeup. |

Also check the RPC Differences page under Developer Essentials before the indexer work, and default
the indexer to finalised blocks.

## 5. Build schedule — 20 days

Three gates. Each gate is a demonstrable fact, not a percentage. Do not start the next phase until
the current gate passes.

### Week 1 (23–29 Sep) — cryptography and derivation

| Day | Work | Gate |
| --- | --- | --- |
| 1 | Foundry scaffold. Testnet access, faucet, deploy a trivial contract. Call `0x08` and record its real gas cost. | Pairing gas measured on Monad testnet — a number, written down |
| 2 | Integrate `bls-solidity`. Verify a live evmnet round on testnet. | Real round verified on-chain, floor bumped |
| 3–5 | Fixed-point library and Tick derivation in Solidity. | Sampled conformance vectors pass bit-for-bit |
| 6–7 | Registry. Open Rooms across every price model. | 50 Rooms open on testnet; specs provably immutable |

Day 1–2 is the highest-risk work in the whole plan and it is also the cheapest to fail at. If the
pairing does not work on Monad as documented, we find out on day one and still have 19 days to
change course.

### Week 2 (30 Sep – 6 Oct) — the ladder

| Day | Work | Gate |
| --- | --- | --- |
| 8–10 | Checkpoint posting, challenge window, unattended finalize. Poster bot with measured gas limits. | Checkpoints finalize unattended over a multi-hour run |
| 11–13 | Bisection game and terminal resolve. Adversarial test suite. | Dishonest poster loses, in tests and once live on testnet |
| 14 | Full conformance sweep across the complete vector set. Gas table for every entry point. | Full sweep green; CU/gas table complete |

### Week 3 (7–13 Oct) — product and submission

| Day | Work |
| --- | --- |
| 15–16 | Market: parimutuel round, entry buffer above the floor, claim. |
| 17 | Frontend: live chart derived in-browser from the beacon with zero RPC, Room browser, wallet connect. |
| 18 | Indexer for checkpoint and tick history. Wire the chart's "verify against chain" toggle. |
| 19 | Demo video, writeup, final deploy, freeze. |
| 20 (13 Oct) | Submit in the morning. Deadline-day RPC congestion is real and self-inflicted deadlines are free. |

### Cut lines

Decide against these honestly rather than shipping something half-finished:

- **Behind at day 13** → ship the ladder with a single-step challenge instead of full bisection. Say so explicitly in the writeup and explain the design that would replace it. Judges reward a clear known-limitation over a vague claim.
- **Behind at day 16** → drop Market and submit as verifiable market infrastructure with the derivation demo. The chart that anyone can recompute is a stronger demo than a rushed betting UI.
- **Never cut the live fraud proof.** It is the thing nobody else will have.

## 6. Conformance strategy

The derivation must be bit-identical to the specification, and we should be able to prove that
before deployment rather than after.

- **Fast path** (CI, every commit): a trimmed fixture — roughly 2,000 rounds sampled across every price model and every edge case — packed as hex and read by a Foundry test. JSON parsing at scale inside Foundry is slow enough to discourage running the suite; a packed fixture keeps it under a few seconds so it actually gets run.
- **Full path** (nightly and before submission): stream the complete vector set through the deployed library from a scripted harness, comparing every field. This is the "independent reimplementation matches bit-for-bit" claim, and it is worth a line in the submission.
- **Adversarial path:** fuzz the ladder. Random epoch sizes, random corrupted ticks, a poster that lies at the first tick, the last tick, and the middle. The invariant under test is single-sentence: *a dishonest poster with any strategy loses to one honest challenger.*
- **Differential path:** the TypeScript derivation used by the frontend and the Solidity derivation must agree on every vector. Two independent implementations disagreeing is a bug in the spec, not in one of them.

Rounding is the whole game. `mul`, `div`, `sqrt`, `exp`, `ln` — each one truncates toward zero, and
every reimplementation must inherit that from the language's `/` operator rather than from a
rounding helper.

## 7. Sponsor bounties

Track prize is $30,000 across three teams. Bounties are additive and several cost us almost nothing.

| Bounty | Value | Fit | Effort |
| --- | --- | --- | --- |
| Envio — Best Use of Envio | $1,000 | We need a checkpoint and tick indexer regardless | Low — take it |
| Privy / Dynamic — Best Use | $5,000 each | Wallet onboarding on the frontend | Low — pick one, a day of work |
| Perpl — Best use of the API | $5,000 | A perpetual on a Room index, funding keyed to the beacon | Medium |
| Perpl — Best analytics / risk tool | $3,000 | A risk surface over the ladder: open challenges, bond exposure, epoch lag | Medium — reuses frontend work |
| Kuru — Bring new assets and markets | $5,000 | Direct on the face of it, but a Room is not an asset: no supply, nothing to hold. Listing one on an order book requires a vault-backed wrapper, which is a real design decision, not a weekend adapter. | High — only if week 2 finishes early |
| ack3 — security scan for every winning team | $15,000 pool | An adversarial fraud-proof game is exactly what we would want scanned | Free if we win |
| Chainlink — Best workflow with CRE | $3,000 | Skip. The protocol deliberately requires no oracle. Bolting one on to chase $3,000 weakens the central claim. | — |

Aim: Track 01 placement + Envio + one wallet bounty + one Perpl bounty. Do not distort the product
to chase a bounty; the judging bar is "could this be a real app that people actually use."

## 8. Submission package

- **Demo video, 2–3 minutes.** Structure: open a Room → watch it tick → recompute the chart locally with the network disconnected → post a dishonest checkpoint → challenge it → watch the liar lose their bond. That last beat is the whole submission.
- **Live testnet deployment** with verified contracts and addresses in the README.
- **A verifiable claim, not a screenshot.** "Here is a Room ID and a round. Derive it yourself from the public beacon and confirm it matches the chain." Judges who try it will remember it.
- **Gas table for every entry point**, measured on Monad. Numbers beat adjectives.
- **An explicit statement of what was built inside the window.** The rules allow existing projects provided the demonstrated work was created during the six-week window and judges can verify what was built during the competition. The Monad implementation is the submission; the protocol design predates it. Say that plainly and up front — a judge who discovers it themselves will discount everything else.

## 9. Risk register

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| Pairing behaves differently or costs more than expected on Monad | Low | Day 1 gate. Fail fast while there is still time to change course. |
| Bisection in Solidity overruns | Medium-high | Day 13 cut line to a single-step challenge. Write the adversarial tests before the game, so "done" is defined by a failing test turning green. |
| Fee-on-gas-limit surprises the bots | Medium | Measure before automating. Alarm on balance headroom. Never send a padded limit. |
| Three weeks against teams who had six | Certain | Sequence by risk, not by enthusiasm. Cut lines decided in advance and honoured. |
| Product reads as a gambling app to a judge | Medium | Lead with un-riggable market infrastructure and the fraud proof. The rake is disclosed honestly, but it is not the headline. |
| Deadline-day infrastructure failure | Low | Submit on the morning of the 13th with a frozen build from the 12th. |

## 10. References

**Metropolis**

- Hackathon: https://monad.xyz/metropolis

**Monad documentation**

- Docs home: https://docs.monad.xyz/
- Developer Essentials — differences from Ethereum: https://docs.monad.xyz/developer-essentials/differences
- Precompiles (incl. `0x08` repricing, BLS12-381, P256): https://docs.monad.xyz/developer-essentials/precompiles
- Network information — chain IDs, RPC endpoints, explorers, faucet: https://docs.monad.xyz/developer-essentials/network-information
- RPC differences — linked from Developer Essentials; read before the indexer work
- Mainnet: chain ID 143, native token MON, public RPC https://rpc.monad.xyz. Testnet chain ID and faucet: see Network Information.
- 300ms blocks / 600ms finality: https://monad.xyz/blog/300ms-block-times

**drand**

- Developer docs: https://docs.drand.love/developer/
- HTTP API: https://docs.drand.love/developer/API-v2/drand-http-api/
- Solidity BLS verifier: https://github.com/randa-mu/bls-solidity
- evmnet — scheme `bls-bn254-unchained-on-g1`, 3s period, chain hash `04f1e9062b8a81f848fded9c12306733282b2727ecced50032187751166ec8c3` (verify against the API before hardcoding)

## 11. The strategic case

The prize money is the smaller half of the reason to do this.

An EVM implementation is not hackathon throwaway work — it is the second host chain, built under a
deadline with an audit and $250,000 attached. Twenty days of forcing function on work that was
already on the roadmap is a good trade even if we place nowhere.

Judge the decision on that basis, and treat any placement as upside.
