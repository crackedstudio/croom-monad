# Verifying a drand round on Monad — cost and spread

**Measured 2026-09-23**, 32 real evmnet rounds sampled across ~30,000 rounds of history, each
verified through `bls-solidity` on Monad testnet by keyless `eth_call`
(`src/probe/BeaconVerifyReport.sol`, `bin/sample-verify-gas.sh`). Raw data: `verify-gas.csv`.

**32 of 32 verified.** The cryptography works on Monad against live beacon data — not a synthetic
input, not a local EVM.

| Stage | min | max | mean | spread |
| --- | --- | --- | --- | --- |
| `hashToPoint` | 44,881 | **54,644** | 49,390 | 9,763 |
| `verifySingle` (pairing) | 565,927 | 565,928 | 565,927 | **1** |
| total | 611,011 | **620,774** | 615,520 | 9,763 |

The pairing is flat to within a single gas unit, exactly as `bench/precompiles.md` predicts: the
input is always twelve words, so the cost is always `225,000 + 2 × 170,000`.

## Hash-to-point is trimodal, and that is structural

The 32 samples fall into three tight clusters:

| Cluster | Rounds | Reading |
| --- | --- | --- |
| ~44,900 – 45,100 | 9 | neither `mapToPoint` call took the expensive branch |
| ~49,700 – 50,000 | 17 | one of the two did |
| ~54,500 – 54,650 | 6 | both did |

The clusters are ~4,800 gas apart, and `hashToPoint` calls `mapToPoint` exactly twice. SVDW takes a
Legendre symbol and conditionally a square root, both through the `modexp` precompile; each call
either pays for that branch or does not. Three outcomes, three clusters, evenly spaced. The ±130
gas of variation inside each cluster comes from the round number's own bytes.

This matters because **it is not noise that averages out**. It is a per-round property, decided by
the beacon, that we cannot predict before we have the round and cannot influence at all.

## The gas limit policy

On Monad the limit is the price (`bench/fee-model.md`), so the limit is a two-sided mistake:

- **Too low** — the transaction reverts *and* is billed in full. Worst outcome available.
- **Too high** — the padding is charged as real money on every single verification.

A limit set from an average round would be under water on ~19% of rounds, and each of those
failures costs full freight while advancing nothing. So the limit is set from the **structural**
worst case — both branches taken — rather than from the sample maximum, which is only the worst of
32 draws.

The consolation is that the spread is small against the total: 9,763 gas on ~616,000 is **1.6%**.
Paying worst-case on every round costs at most 1.6% more than paying exactly, which is cheap
insurance against a class of failure that costs 100%.

| | gas |
| --- | --- |
| `hashToPoint`, both branches | 54,644 |
| pairing | 565,928 |
| **measured worst case** | **620,772** |

`Entropy` will add intrinsic gas, calldata, G1 validation and the floor write on top of this. The
final limit gets set in step 2.3 against the real contract, and re-derived in step 7.4 — this is
the floor it builds on, not the answer.

## Why the sample is the shape it is

Rounds were taken at a stride of 977 from the head of the chain, spanning ~30,000 rounds (~25 hours
of beacon time). A stride avoids sampling a pattern; consecutive rounds would have told us about one
moment rather than about the distribution. All three clusters appeared, which is the evidence that
the trimodal structure is real and not an artifact of where we happened to look.
