# Gas table — measured on Monad

**Measured 9 October 2026** against the live deployments on Monad testnet (chain `10143`), at
103–105 gwei.

Every figure is either `eth_estimateGas` **against the deployed contract** — which applies Monad's
own schedule — or a deployment's receipt. Nothing here is a local-EVM estimate, because forge's EVM
prices BN254 at Ethereum's rates and is wrong by up to 2.4× (`bench/gas-estimation.md`).

Note that on Monad `receipt.gasUsed` reports the **billed** gas, which equals the limit, so
receipts cannot be used to read execution cost (`bench/fee-model.md`). Deployment receipts are the
exception: code deposit is priced the same on both chains and the limits were sized from accurate
estimates.

## Entry points

| Contract | Function | Gas | Cost at 103 gwei | Source |
| --- | --- | ---: | ---: | --- |
| `Entropy` | `verifyRound` (view) | 645,623 | — | `eth_estimateGas` |
| `Entropy` | `proveRound` | 656,948 | 0.0677 MON | `eth_estimateGas` |
| `Registry` | `openRoom` | 77,709 | 0.0080 MON | `eth_estimateGas` |
| `Ladder` | `post` | 107,421 | 0.0111 MON | `eth_estimateGas` |
| `Ladder` | `disproveTransition` | 817,530 ⚠️ | 0.0842 MON | live transaction, **billed** |
| `Market` | `open` | 130,338 | 0.0134 MON | `eth_estimateGas` |

⚠️ `disproveTransition` is the one figure that is a billed limit rather than an execution cost. The
only checkpoint on this deployment is already `Rejected`, so the call now reverts and cannot be
estimated without posting another lie. The real cost is bounded below by `verifyRound` (645,623),
since the disproof verifies a beacon signature, plus two Merkle folds and one re-executed round.

## Deployments

| Contract | Runtime size | Deploy gas | Cost |
| --- | ---: | ---: | ---: |
| `Entropy` | 9,874 B | 2,834,001 | 0.2919 MON |
| `Registry` | 3,420 B | 1,020,614 | 0.1072 MON |
| `Ladder` | 15,298 B | 4,342,651 | 0.4473 MON |
| `Market` | 9,343 B | 2,686,981 | 0.2768 MON |

All four are far inside Monad's 128 KB contract limit — the largest uses 12% of it. The protocol
ships as four plain contracts with no proxy or diamond indirection, which the size limit makes
possible and which keeps the deployed bytecode the same thing as the audited source.

## Where the cost actually goes

`proveRound` dominates everything, and it is **97% one precompile**:

| | gas |
| --- | ---: |
| `ecPairing`, 2 points | 565,928 |
| hash-to-curve (SVDW, `modexp`) | 44,881 – 54,644 |
| intrinsic, calldata, validation, one storage write | ~45,000 |
| **total** | **~657,000** |

That is the number the architecture is built around. At 3-second rounds, verifying every round
would cost roughly **1,600 MON a day** — not expensive, impossible. The ladder exists so the chain
verifies sparsely and commits to everything in between, and the fraud proof exists so those
commitments are safe to believe.

`openRoom` at 77,709 is the counterweight: opening a Room costs about **one eightieth** of proving
a round. Supply is cheap and verification is dear, which is the right way round for a protocol
whose supply is user-generated.

## Comparison with the Solana reference

Different units, so the absolute numbers do not compare. The share of a transaction's budget does:

| | Solana (reference) | Monad (this port) |
| --- | --- | --- |
| Pairing, 2 points | 49,125 CU | 565,928 gas |
| Full round verification | 236,152 CU | ~657,000 gas |
| Share of the per-transaction budget | **17%** of 1.4M CU | **2.2%** of 30M gas |
| Hash-to-curve | witness-verified SVDW | direct — `modexp` works |

The reference verifies hash-to-curve with **witnesses** because Solana's `sol_big_mod_exp` is a
stub and a real modular exponentiation would cost over 1M CU. On Monad the precompile works, so the
EVM port needs no witness machinery at all — the same protocol, with the host chain deciding how
hard the cryptography is to land.

## Method

```bash
cast estimate <address> "<signature>" <args> --rpc-url monad_testnet --from <sender>
```

Read-only, needs no key, and applies the node's own gas schedule. For anything not yet deployed,
the constructor-return probes in `src/probe/` measure the same way without deploying at all.
