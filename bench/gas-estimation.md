# Never let a tool estimate gas for you on Monad

**Found the expensive way, 3 October 2026.** Cost: one failed transaction and 0.0284 MON.

## What happened

`forge script` deployed `Entropy` and then called `proveRound` in the same broadcast. The deployment
succeeded. The call **ran out of gas** at 276,012 — while the same call, estimated by the Monad node
itself, needs **669,285**.

| | gas |
| --- | --- |
| `eth_estimateGas` on Monad, for the exact call | **669,285** |
| limit `forge script` set from its own simulation | 276,012 |
| shortfall | 393,273 — **2.42×** |

## Why

`forge script` estimates by executing the transaction in **its own EVM**, which uses **Ethereum's**
gas schedule. Monad reprices the BN254 precompiles (`bench/precompiles.md`):

| | Ethereum | Monad | difference |
| --- | --- | --- | --- |
| `ecPairing`, 2 points | 113,124 | 565,928 | **+452,804** |

That single line is more than the whole shortfall. Everything else — `ecMul` at 5×, `ecAdd` and
`ecRecover` at 2×, cold storage at 8,100 against 2,100 — pushes the same way.

PLAN.md §4 says "do not budget the pairing from Ethereum's published cost." We did not. **The tool
did**, silently, on our behalf.

## Why it is worse here than elsewhere

On a chain that bills `gas_used`, an under-estimate is an annoyance: the transaction reverts and
costs little. On Monad the **limit is the price** (`bench/fee-model.md`), so a transaction that runs
out of gas is charged for every unit of the limit it failed to complete within. An under-estimate is
billed exactly like a success.

## The rule

> **Any transaction touching a repriced precompile — `0x01`, `0x06`–`0x0a` — gets an explicit gas
> limit from a measurement, never from a tool's estimate.**

Three ways to get a trustworthy number, in order of preference:

1. **`eth_estimateGas` against the deployed contract on Monad.** The node applies its own schedule, so this is authoritative. Free, and needs no key.
2. **A constructor-return probe** (`src/probe/`), for measuring before anything is deployed.
3. **A previous receipt** — but remember `receipt.gasUsed` reports the *billed* figure on Monad, not the executed one, so a receipt tells you what a limit *was*, never what it needed to be.

`forge script --gas-estimate-multiplier` is not the fix: it scales every transaction in the script,
including deployments whose estimates are already correct, and overpaying a 2.8M-gas deployment by
2.5× to rescue a 670k call costs far more than it saves.

## Measured: how far wrong a tool's estimate is, by transaction shape

Two shapes measured on Monad against what forge's own EVM estimates:

| Transaction | forge estimate | real (Monad `eth_estimateGas`) | factor |
| --- | --- | --- | --- |
| `Entropy.proveRound` — pairing, hash-to-curve, one fresh slot | 276,012 | **669,285** | **2.42×** |
| `Registry.openRoom` — one cross-contract read, one fresh slot | 63,086 | **77,709** | **1.23×** |

The factor is **not a property of the chain, it is a property of the transaction**. It tracks how
much of the work sits in repriced operations:

- `proveRound` is dominated by `ecPairing`, repriced 5×, so it lands near 2.4×.
- `openRoom` does ordinary work plus a cold cross-contract read (10,100 against 2,600) and one fresh storage slot (27,900 against 22,100), so it lands near 1.2×.

**There is no single safe multiplier.** We used 1.8× for the 50-Room broadcast, which was
over-cautious by 46% and cost **0.188 MON** of pure padding — a cheaper mistake than the
under-estimate that preceded it, and still a mistake. The default is now 1.3×, measured.

A multiplier is only appropriate when every transaction in a batch has the same shape, as the 50
Rooms did. For a mixed script, measure each call.

## What changed

Deployment and proving are now separate targets. Proving sends with a measured limit:

| | gas |
| --- | --- |
| measured, first call (pays 17,000 state growth for a fresh slot) | 669,285 |
| worst-case hash-to-point, +9,763 over this round (`bench/verify-gas.md`) | 679,048 |
| **limit used** | **700,000** |

About 3% over worst case — roughly 0.003 MON of padding per call at 103 gwei, against a failure that
costs the entire limit. Later calls are cheaper by the 17,000 state-growth charge, which is a second
limit the poster bot will want (step 5.4).
