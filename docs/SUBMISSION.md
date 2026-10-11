# Croom on Monad — submission notes

Companion to the [README](../README.md), which carries the addresses, the verifiable claim and the
fraud proof. This is the argument.

## Why this instrument needs Monad

Track 01's framing is that fast settlement makes new instruments practical, with "perpetuals whose
funding updates every block" as the worked example. The claim here is narrower and sharper.

**The beacon emits a round every 3 seconds.** A market round must open, lock, resolve and pay
inside that window, or the instrument is not what it says it is. Monad finalises deterministically
in 600 ms at 300 ms block times, so a full settlement cycle fits inside a single beacon tick with
room to spare. On a 12-second chain this instrument is not slow — it does not exist.

We are not claiming Monad is the only chain that can run this. The reference runs on Solana. The
claim is that the **cadence** is what the chain unlocks, and three specific things made the port
land:

**The cryptography is native.** Beacon verification is a BN254 pairing check, and Monad supports
the full Ethereum precompile set. It is a precompile call, not a hand-rolled circuit.

**`modexp` works, which it does not on Solana.** The reference verifies hash-to-curve with
*witnesses* — the caller supplies hints the program checks — because Solana's `sol_big_mod_exp` is
a stub and a real modular exponentiation would cost over 1M CU. On Monad the precompile works, so
the EVM port needs no witness machinery at all. Verification is 2.2% of a Monad transaction's
budget against 17% of a Solana one. The same protocol, and the host chain decides how hard the
cryptography is to land.

**Cheap terminal steps make an honest challenger viable.** A fraud proof is only credible if the
final re-execution is affordable to submit. Disproving a lie costs about 0.08 MON and requires no
bond. Watching is close to free, which is the property the system's safety actually depends on.

## What we did not expect

Six things cost real time, and all six are written down because they generalise to any EVM port.

**The pairing is 5× Ethereum.** `225,000 + 170,000/point`, measured, not quoted. That single number
determined the architecture: verifying every round would cost ~1,600 MON a day, so the chain must
verify sparsely and commit to the rest. Had it come back at Ethereum prices we might have been
tempted into a lazier design that would not have scaled.

**Monad charges the gas limit, and receipts report the billed figure.** The first means a
transaction that runs out of gas is charged exactly like one that succeeds. The second means you
**cannot profile execution cost from receipts** — which is how our first two attempts at measuring
the fee model produced confident, wrong answers. Every figure in `bench/` comes from `eth_call`
probes or `eth_estimateGas` for that reason.

**Tools estimate with Ethereum's schedule.** `forge script` under-sized a `proveRound` limit by
2.42× and the transaction died — billed in full, naturally. The correction factor is a property of
the *transaction*, not the chain: 2.4× for a pairing-dominated call, 1.23× for a storage-heavy one.
There is no single safe multiplier, and we overpaid 0.19 MON learning that from the other direction.

**Storage pages change what you should store.** A cold page is 8,100 gas and a new slot costs
17,000 while overwriting a warm one costs 100 — a 170× difference. That is not a micro-optimisation;
it argues for keeping only the commitments still inside the challenge window and letting everything
older be reconstructible from events and the beacon. The gas schedule and the architecture wanted
the same thing.

**The library's obvious entry point is the wrong one.** `bls-solidity`'s `BN254SignatureScheme`
derives its domain separation tag from `block.chainid`. Correct for its authors' network, wrong for
drand — and the failure mode is a verifier that compiles, deploys, costs full price, and silently
rejects every genuine beacon. There is now a test whose only job is to ensure nobody rediscovers it.

**Solidity has traps Rust does not.** Memory structs alias on assignment, so a test that mutates a
"copy" mutates the original and *passes*. EVM memory never frees, so eagerly-built assertion
messages exhausted the test runner across 10,000 rounds. And `exp_wad` floors a possibly-negative
quotient while Solidity's `/` truncates — getting that wrong is an answer wrong by a factor of two,
for half of all inputs. All three are in [`porting-notes.md`](porting-notes.md).

## What the port contributed back

**A finding against the specification.** Floor freshness is described as an operator concern. We
think it is a safety property, and the inequality in the spec's reasoning runs the wrong way. It is
demonstrated by a passing test rather than argued in prose, and the write-up admits that the obvious
fix reintroduces the time dependence the design was meant to remove.
See [`findings/0001-floor-freshness.md`](findings/0001-floor-freshness.md).

**A simpler fraud proof, and the correction that makes it sound.** The reference bisects. We
observed that bisection is only necessary when a challenger cannot compute the truth cheaply — and
here they can, because the derivation is deterministic and public. A one-shot "name the inconsistent
adjacent pair" disproof is *complete*, and it removes the challenger's bond entirely.

The first version of that was wrong in a way worth recording. A disproof must exhibit a committed
leaf with its Merkle path, and a poster who published only a root could withhold the preimages — so
a challenger would know the root was false and be unable to prove it. Bisection had been supplying
data availability implicitly, by forcing disclosure at every step of the game, and removing it
removed that too. The fix is that `post` takes the leaves and derives the root, which costs about
56 bytes per round and additionally makes structurally invalid trees unpostable rather than merely
disprovable.

We found this by re-reading our own argument for its premises rather than its conclusion, which is
the kind of review that is easy to skip when the tests are green.

**A third implementation.** Rust produced the vectors, TypeScript reproduces them, and Solidity now
reproduces them on Monad — written last, against an artefact frozen before it existed. Three
implementations in three languages agreeing bit-for-bit is a stronger statement than the two the
original plan expected.

**A measurement technique.** The constructor-return probes in `src/probe/` report a live node's gas
schedule through a plain `eth_call`: no deployment, no key, no funds. The day-one gate was answered
before a faucet claim had cleared, and the same trick would answer it on any EVM chain.

## Honest accounting

The protocol design, the Rust implementation, its SDK and the conformance vectors predate the
window. The Solidity implementation, every Monad measurement, the frontend's chain layer and the
finding above were built inside it. The git history is the evidence: one commit per step, tagged at
each gate.

Scope was cut twice under deadline and both decisions are recorded with their reasoning in
[`decisions/`](decisions/) — including one taken *against* the plan's own advice, which is the sort
of thing worth being able to point at afterwards.
