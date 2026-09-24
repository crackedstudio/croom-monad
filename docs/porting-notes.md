# Porting `croom-core` to Solidity

The Solidity derivation is a **port of a frozen reference**, not an independent design. Everything
here is about reproducing `reference/croom-core` exactly, and about the places where Solidity makes
that harder than Rust does.

Authority order: the vectors, then `core-v1.md`, then protocol spec v1.1. See [`spec/README.md`](../spec/README.md).

## 1. The reference is `i128`, Solidity has no `i128` arithmetic

`core-v1.md` §1: values are `i128` scaled by WAD, and "intermediates never overflow because
products are formed in 256 bits."

In Solidity we hold values in `int256` but must **enforce `i128` bounds on every result**, because:

- two `i128` operands multiply to at most ~2^254, which fits `int256` exactly — so `mul_div` needs no 512-bit trick, which is a real simplification over the usual full-width `mulDiv`;
- but a result that exceeds `i128` is an **error in the reference**, and Solidity would happily carry it. A port that omits the bound accepts inputs the reference rejects, and diverges precisely on the cases the vectors exist to catch.

So: compute in `int256`, range-check against `type(int128).min/max` on every result that the
reference declares `i128`.

## 2. Truncation versus floor — they are different, and both appear

`core-v1.md` is explicit: "Truncate" means toward zero, `⌊ ⌋` means toward −∞. **Both are used.**

| Use | Direction |
| --- | --- |
| `mul_div`, `div_int`, `div_wad` | truncate toward zero |
| `exp_wad` step 2, `k = ⌊x / LN2_WAD⌋` | **floor**, and `k` may be negative |
| `exp_wad` step 4, `k < 0`: `⌊sum / 2^(−k)⌋` | **floor** |
| `ln_wad` step 1, `m = ⌊x / 2^k⌋` | floor (operands positive, so identical to truncation here) |
| `uniform_wad` | floor |

Solidity's `/` truncates. **Every floor on a possibly-negative value needs an explicit helper**, or
`exp_wad` diverges for all negative inputs — which is half of them.

```solidity
function floorDiv(int256 a, int256 b) internal pure returns (int256 q) {
    q = a / b;
    if ((a % b != 0) && ((a < 0) != (b < 0))) q -= 1;
}
```

`test/Toolchain.t.sol` asserts Solidity's truncation direction, and was the first test in this
repository. It now needs a sibling asserting the floor helper.

## 3. Association order is copied literally

Because every division truncates, `(a·b/WAD)·c/WAD` and `a·b·c/WAD²` are different numbers, and a
one-unit difference is a different Merkle root and a lost fraud proof. Every expression is
transcribed from `core-v1.md` with its parenthesisation intact. No reassociation, ever, however
obviously equivalent it looks in exact arithmetic.

## 4. Keccak, not SHA3

`core-v1.md` §2: "Keccak-256 (Ethereum/Solana keccak, pad 0x01 — not SHA3)." Native on the EVM, so
free to us. The hazard is only in off-chain tooling: Node's `crypto` offers `sha3-256`, which
differs in padding and produces a plausible-looking wrong answer.

`R_r = SHA-256(σ_r)` is **SHA-256**, not keccak — the one place the other hash appears.

## 5. Merkle pairs are sorted

`node(a,b) = H(min(a,b) ‖ max(a,b))`, compared **byte-wise**. Sorted-pair Merkle, so proofs carry no
direction bits. In Solidity, comparing two `bytes32` as `uint256` is byte-wise big-endian
comparison, which is what the reference means — but this is worth a test rather than an assumption.

Leaves are **double-hashed**: `leafHash = H(H(leafBytes))`. Odd elements carry up unchanged. An
empty list roots to 32 zero bytes.

## 6. Monad has `modexp`; Solana does not

`reference/croom-core/docs/measurements.md` explains that Solana's `sol_big_mod_exp` is a stub, so
the reference verifies SVDW hash-to-curve with **witnesses** — the caller supplies hints and the
program checks them, because a real modular exponentiation would cost over 1M CU.

On Monad the `modexp` precompile works, and our whole hash-to-point measures 44,881–54,644 gas
(`bench/verify-gas.md`). **The EVM port needs no witness machinery at all.** That is a genuine
simplification the port gets for free, and worth a sentence in the writeup: the same protocol, and
the host chain decides how hard the cryptography is to land.

## 7. Cost comparison across hosts

| | Solana (reference) | Monad (this port) |
| --- | --- | --- |
| Pairing, 2 pairs | 49,125 CU | 565,928 gas |
| Full `verify_round` | 236,152 CU | ~616,000 gas |
| Share of per-transaction budget | 17% of 1.4M CU | ~2% of 30M gas |
| Hash-to-curve | witness-verified SVDW | direct, `modexp` available |

Different units, so the absolute numbers do not compare — the budget share does, and Monad has more
headroom for the fraud proof's terminal step.
