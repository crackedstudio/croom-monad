# Croom derivation spec — 1. Arithmetic

**Status: draft, written 2026-09-24.** This document and its siblings in `spec/` are the authority
that `Tick.sol` and the TypeScript derivation are both measured against. Where an implementation
and this document disagree, the document is right until it is amended — and amending it means
regenerating every conformance vector.

## 1.1 Representation

All prices, rates and intermediate values are **`int256` fixed point with 18 decimals**.

```
ONE = 1_000_000_000_000_000_000        // 10^18, the value 1.0
```

There is no floating point anywhere: not in the contracts, not in the frontend, not in the vector
generator, not in the indexer. A `double` cannot hold 18 significant decimals exactly, so a single
`Number` anywhere in the pipeline silently destroys the claim this project is built on.

## 1.2 Division truncates toward zero

Every division in this spec truncates toward zero — `7 / 2 = 3` and `-7 / 2 = -3`, **not** `-4`.

This is inherited from the language operator, never from a rounding helper:

| Language | Operator | Behaviour |
| --- | --- | --- |
| Solidity | `/` on `int256` | truncates toward zero ✅ |
| TypeScript / JavaScript | `/` on `BigInt` | truncates toward zero ✅ |
| Rust | `/` on `i128`/`i256` | truncates toward zero ✅ |
| Go | `/` on `big.Int` `Quo` | truncates toward zero ✅ |
| **Python** | `//` | **floors — wrong for negatives** ❌ |

> **The Python trap.** `-7 // 2` is `-4` in Python, not `-3`. A vector generator written in Python
> diverges from Solidity on every negative intermediate, and only on negative intermediates — so it
> passes every test with an upward-drifting Room and fails mysteriously on a downward one. Any
> Python in this pipeline must use an explicit truncating helper:
>
> ```python
> def div(a: int, b: int) -> int:
>     q = abs(a) // abs(b)
>     return -q if (a < 0) != (b < 0) else q
> ```

`test/Toolchain.t.sol` asserts the Solidity half of this, and was deliberately the first test
written in the repository.

## 1.3 Association order is part of the spec

Because every division truncates, **`(a * b / ONE) * c / ONE` and `a * b * c / (ONE * ONE)` are
different numbers.** They differ by up to one unit in the last place, which is a different price,
which is a different Merkle root, which is a lost fraud proof.

Every formula below is written with explicit parentheses. Implementations reproduce that
parenthesisation literally. An optimiser may reassociate only where it can prove exactness, which
for truncating division it essentially never can.

## 1.4 Overflow

All arithmetic is checked. `int256` holds roughly ±5.7 × 10^76; the widest intermediate any model
below produces is `vol × z × price` at about 10^60 for the maximum permitted price. There is no
`unchecked` block in the derivation, and an overflow is a bug in spec validation rather than
something to wrap around.

## 1.5 Hashing

Keccak-256 throughout, via `abi.encodePacked` with the field widths stated at each use. Keccak is a
native EVM opcode and measured at Ethereum's price on Monad (`bench/precompiles.md`), so the hash
layer is free to us in a way `sha256` would not be.

`abi.encodePacked` is used only over fixed-width values, never over two adjacent dynamic types, so
no ambiguous encoding can arise.
