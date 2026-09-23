# The fee model — measured, not assumed

**Measured 2026-09-23.** PLAN.md §4 calls fee-on-gas-limit "the single biggest behavioural
difference" and sizes every bond and bot budget against it. It is now verified on testnet rather
than inherited from documentation.

## The experiment

One transaction to `GasProbe.checkPairing` at
[`0x5222AC02…`](https://testnet.monadscan.com/address/0x5222AC024a4D74435f943A889C111DBFe330215B),
with a gas limit deliberately padded far above what the call needs.

| | |
| --- | --- |
| tx | [`0x6141a30f…`](https://testnet.monadscan.com/tx/0x6141a30f87630da37d88e070b967a8bb56f1e3c8ec7a6c3d4f48b89ef4a11c4d) |
| status | **1 — success**, no revert |
| gas limit | 2,000,000 |
| `eth_estimateGas` for the same call | **597,880** |
| receipt `gasUsed` | **2,000,000** |
| gas price | 102 gwei |
| **actually debited** | **0.204000 MON** |

Cost under each model:

| Model | Predicted | Matches? |
| --- | --- | --- |
| billed on execution — 597,880 × 102 gwei | 0.060984 MON | ✗ |
| billed on the limit — 2,000,000 × 102 gwei | **0.204000 MON** | ✅ exact |

**Monad charges `gas_bid × gas_limit`.** A successful transaction that used 598k of a 2,000,000
limit paid for all 2,000,000. Padding a limit by 3.3× cost 3.3× the fee.

## The part that is not in the docs: receipts report the billed amount

`receipt.gasUsed` came back as **2,000,000** — the limit — for a call that executes in 597,880. The
receipt reports what was *charged*, not what was *executed*.

This broke two measurement attempts before it was understood. The first script compared the balance
delta against `receipt.gasUsed × price` and concluded "GAS_USED" both times, because on Monad that
comparison is circular: the receipt's figure already **is** the billed amount, so both models agree
by construction and the test can never fail. The verdict was an artifact of the method.

Consequences that outlive this measurement:

- **You cannot profile execution cost from production receipts on Monad.** Every gas figure in `bench/` comes from `eth_call` probes or `eth_estimateGas` for exactly this reason. That was originally a convenience — no key required — and turns out to be the only correct method.
- **Any tooling that reads `gasUsed` to mean "what this cost to run" is wrong here.** That includes the obvious instinct of measuring the poster bot by looking at its own receipts (step 5.4). The bot must record the estimate it used and the limit it set, because the chain will not tell it afterwards.
- **A padded limit is a direct, silent overpayment.** Not a cap — a price. The two inconclusive runs cost 0.204 MON each against ~0.061 MON of actual execution: 0.286 MON of pure padding, on two transactions.

## Carried into the build

| Consequence | Step |
| --- | --- |
| Bonds sized against worst-case **limit**, never expected consumption | 5.2, 6.5 |
| Poster and challenger set limits from `bench/`, never from a padded default; every limit traceable to a measurement | 5.4, 7.4 |
| Bots log `(estimate, limit)` at send time — receipts cannot reconstruct it | 5.4 |
| A reverting `0x08` burns the whole limit, and the limit is the price: a bad signature costs full freight (`bench/precompiles.md`) | 2.3 |
