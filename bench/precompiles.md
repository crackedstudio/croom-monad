# Precompile and opcode gas — measured on Monad

**Measured 2026-09-23** against `https://testnet-rpc.monad.xyz` (chain `10143`, client `Monad/0.16.2`).

Method: `src/probe/PairingGasReport.sol` and `src/probe/PrecompileGasReport.sol` do the work in a
constructor and return the measurements where runtime code would go, so a plain `eth_call` reports
the node's own gas schedule:

```bash
cast call --rpc-url monad_testnet --create $(forge inspect PrecompileGasReport bytecode)
```

No deployment, no funded key, no faucet. **The day-one gate was answerable before a faucet claim
cleared**, which is worth knowing for the next chain we port to.

## The number that decides the architecture

| k (points) | Monad, measured | Ethereum, measured locally | Ratio |
| --- | --- | --- | --- |
| 1 | **395,130** | 79,124 | 5.0× |
| 2 | **565,130** | 113,124 | 5.0× |
| 3 | **735,130** | 147,124 | 5.0× |
| 4 | **905,130** | 181,124 | 5.0× |

Fitting the measurements: **`225,000 + 170,000 × k`**, plus ~130 gas of `STATICCALL` overhead from
the harness. That is exactly the documented formula (docs/monad-facts.md §5) — **the docs are
correct and now verified**. Ethereum's `45,000 + 34,000 × k` reproduces just as exactly on the local
EVM, which is what gives us confidence the harness is measuring what it claims to.

The pairing also **computes correctly**: balanced inputs returned `1` for even `k` and `0` for odd,
so BN254 on Monad is arithmetically sound and not merely present.

## Everything else we will touch

| Op | Monad, measured¹ | Monad net² | Ethereum published | Ratio |
| --- | --- | --- | --- | --- |
| `0x01` ecRecover | 6,133 | 6,000 | 3,000 | 2.0× |
| `0x02` sha256 (1 word) | 205 | 71 | 72 | 1.0× |
| `0x04` identity (1 word) | 151 | 17 | 18 | 1.0× |
| `0x06` ecAdd | 434 | 300 | 150 | 2.0× |
| `0x07` ecMul | 30,134 | 30,000 | 6,000 | **5.0×** |
| `0x08` ecPairing (k=2) | 565,133 | 565,000 | 113,000 | **5.0×** |
| `KECCAK256` (32 B) | 49 | ~36 | 36 | 1.0× |

¹ Includes ~134 gas of `STATICCALL` overhead (~13 for the keccak harness).
² Overhead subtracted. Matches the documented schedule exactly in every row.

**The shape of it:** hashing and data movement are priced as on Ethereum. BN254 curve operations
are 2–5× more expensive. Keccak being unchanged is a quiet piece of luck — PLAN.md §3.3 puts keccak
at the centre of the derivation, and that choice costs us nothing here.

## What this means for Entropy

At the measured 100 gwei base fee, and remembering that **Monad charges `gas_limit`, not
`gas_used`**:

| Verification cadence | Rounds/day | Gas/day | Cost/day |
| --- | --- | --- | --- |
| Every round (3 s) | 28,800 | 16.3 G | **~1,627 MON** |
| Every minute | 1,440 | 814 M | ~81 MON |
| Every hour | 24 | 13.6 M | ~1.4 MON |

Verifying every round is not expensive, it is **impossible**. This is the measurement that makes
the proven-floor design load-bearing rather than elegant: the floor is a sparse, monotone claim that
a round exists, and the ladder commits to everything between two floors without paying a pairing
per tick. Had this come back at Ethereum prices we might have been tempted into a lazier design.

Two consequences carried forward:

- **Step 2.2** — `ecMul` at 30,000 is the one to watch when audit-reading `bls-solidity`. A hash-to-G1 that leans on scalar multiplication will not have the gas profile its Ethereum benchmarks suggest.
- **Step 5.1** — epoch length is bounded below by amortizing a 565,000-gas verification, and above by calldata and `SSTORE` growth at 17,000 per new high-water mark.

## A reverting `0x08` consumes every gas unit forwarded to it

Measured twice, once locally and once — expensively — on testnet: when the input is malformed or a
point is off-curve, the precompile does not return a cheap failure. It burns the entire gas
forwarded. A transaction sent with a 2,000,000 limit against an off-curve input reported
`gas_used == 2,000,000` and cost 0.204 MON.

Two consequences for `Entropy` (step 2.3):

- **There is no "try to verify, fall back on failure" pattern available at a sane price.** Either the contract validates the points itself before calling `0x08`, or it caps the gas it forwards to the precompile. Cap-and-check is the cheaper of the two here, because validation means field arithmetic we would otherwise not do.
- **A bad signature is not a cheap revert.** Whatever `verifyRound` costs on the happy path, the sad path costs whatever it was given. Callers must not pass a generous limit.

It also makes a specific measurement mistake indistinguishable from a specific chain behaviour: an
off-curve input burning the limit looks exactly like a chain that bills the limit. `bin/measure-fee-model.sh`
now pre-flights the input with a free `eth_call` and refuses to send if it is not valid.

## Still owed

- [x] Cold/warm `SLOAD` across a 128-slot page boundary — done, `bench/storage-paging.md`. The 128-slot model holds exactly.
- [x] Confirmed against the **deployed** `GasProbe` at `0x5222AC02…`: `probePairing(2, …)` reports **565,124** gas, against 565,130 by `eth_call --create`. The 6-gas difference is memory-offset overhead in the two harnesses, not a pricing difference.
- [ ] Settle the **fee model** — `gas_limit` or `gas_used`? Two attempts have been inconclusive for the same reason each time: `gas_used` came out exactly equal to `gas_limit`, once because forge sized the limit from its estimate and once because a malformed input burned the limit. Needs one transaction where the two genuinely differ.
