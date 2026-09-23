# Audit-read: `randa-mu/bls-solidity`

**Pinned at `v0.3.0` = `9e10df92d631fab9c46f0ce9cd5c445f857bedcb`.** Read on 2026-09-23 against the
three specific risks that came out of Phase 1's measurements, not as a general code review.

PLAN.md §3.1 says to use this library rather than write a verifier, and to "audit-read it, pin the
commit, and write our own conformance tests against live rounds." This is that read.

## Verdict

**Use it — but use `EvmnetRegistry` as the reference, not `BN254SignatureScheme`.** The library's
BN254 primitives are sound and its evmnet demo is exactly our use case. The packaged signature-scheme
contract is not: it is built for Randamu's own threshold network and would never verify a drand
beacon.

Real evmnet rounds verify correctly on Monad through this library — **32 of 32 sampled rounds
return `true`** (`bench/verify-gas.md`), at 611,011–620,774 gas.

## The trap: two different DSTs

`BN254SignatureScheme` builds its domain separation tag from the chain it is deployed on:

```solidity
DST = abi.encodePacked(application, "-BN254G1_XMD:KECCAK-256_SVDW_RO_", bytes32(block.chainid).toHexString(), "_");
```

drand signs with a fixed tag that has nothing to do with our chain id:

```solidity
string public constant DST = "BLS_SIG_BN254G1_XMD:KECCAK-256_SVDW_RO_NUL_";   // EvmnetRegistry
```

Using the wrong one produces a verifier that compiles, deploys, costs full price to run, and
rejects every genuine beacon. The failure mode is "signature invalid", which is indistinguishable
from a malformed signature, a wrong public key, a round-encoding bug, or a broken pairing. It would
be a bad day to debug on day 12.

`Entropy` therefore takes `BLS` (the library) and `EvmnetRegistry`'s constants, and does **not**
inherit `BN254SignatureScheme`.

## The three risks from Phase 1

### 1. `ecMul` at 30,000 gas — not on our path ✅

`bench/precompiles.md` measured `ecMul` at 5× Ethereum's price, so a hash-to-G1 leaning on scalar
multiplication would not have the gas profile its Ethereum benchmarks suggest.

It does not. `hashToPoint` is `hashToField` (keccak, pure) → `mapToPoint` ×2 (SVDW) → one `ecAdd`.
`scalarMulG1Point` and `scalarMulG1Base` exist in the library but nothing on the verification path
calls them. SVDW uses `modexp` (`0x05`) for Legendre symbol, square root and inverse — priced
"variable" on Monad, which is why it got measured rather than assumed. It is cheap: 44,881–54,644
gas for the whole of hash-to-point, against 565,928 for the pairing. `modexp` is 8% of the cost,
not a hazard (`bench/verify-gas.md`).

### 2. A reverting `0x08` burns everything forwarded — real, and unmitigated here ⚠️

Every precompile call in the library forwards all remaining gas:

```solidity
callSuccess := staticcall(gas(), BN254_ECPAIRING_ADDRESS, input, 384, out, 0x20)
```

`bench/precompiles.md` measured that a malformed or off-curve input makes `0x08` consume every gas
unit it is given, and `bench/fee-model.md` established that on Monad the gas limit **is** the price.
Together: a junk signature passed to `verifySingle` costs the caller the entire transaction limit,
not a cheap revert.

`verifySingle` does not validate its inputs first. `isValidPointG1` and `isOnCurveG1` exist and are
correct, but nothing on the verification path calls them — `EvmnetRegistry.proveRound` goes straight
from `g1Unmarshal` to `verifySingle`.

**This is ours to fix, in `Entropy` (step 2.3), not a bug in the library.** Two options:

- **Validate before calling.** `isValidPointG1` is pure: two comparisons against the field modulus and one on-curve check (`y² == x³ + 3`). Cheap, and it turns a full-limit burn into an ordinary revert.
- **Cap the gas forwarded.** Pass a measured constant instead of `gas()`.

Validation is the better trade here: it costs a few hundred gas on the happy path and removes the
cliff entirely, whereas a gas cap has to be re-tuned every time the measurement moves.

Note the signature is attacker-supplied and the public key is a constant, so G1 is the only input
needing checks.

### 3. Compressed points — not an issue ✅

`g1Unmarshal` takes 64 bytes and `g2Unmarshal` 128, both uncompressed. The drand API serves exactly
those widths (`test/fixtures/drand/README.md`), so no decompression step is needed. Decompression
would mean a modular square root we would otherwise not pay for.

## Public key encoding

The API's 128-byte `public_key` maps onto `BLS.PointG2` with each Fp2 coordinate's imaginary part at
index **1**:

| API word | Struct field |
| --- | --- |
| 0 | `x[1]` |
| 1 | `x[0]` |
| 2 | `y[1]` |
| 3 | `y[0]` |

`verifySingle` then re-orders them back to `x[1], x[0], y[1], y[0]` for the precompile, so the bytes
reach `0x08` in the same order the API served them. Confirmed by `EvmnetRegistry.PUBLIC_KEY()`
matching our pinned `info.json` word for word, and by rounds actually verifying.

## Message encoding

`abi.encodePacked(keccak256(abi.encodePacked(round)))` where `round` is `uint64` — an 8-byte
big-endian round number, hashed once, then hashed to a curve point. Unchained, so no predecessor is
involved and any round verifies in isolation.

## Subgroup checks

`isValidPointG1` checks field range and curve membership but not subgroup membership. **This is
correct for BN254 G1**, whose cofactor is 1: every point on the curve is in the prime-order
subgroup. G2 has a cofactor and would need the check, but our only G2 element is a hardcoded
constant.

## What we are not taking

`BLS2.sol` (BLS12-381), `BLS12381*SignatureScheme`, `QuicknetRegistry`, `ScheduledUpgradeable`,
`ISignatureScheme`. Unused code in `lib/` costs nothing at deploy time, but none of it is on the
path we test, so none of it is in scope.

## Delta to upstream `HEAD`

`v0.3.0..11af179` is 20 commits: formatting, linting, a cargo workspace, dead-code removal, a
`ScheduledUpgradeable` abstract contract, and "bump EVM version to Osaka". Nothing touching BN254
correctness. We stay on the tag — a released tag is reproducible and the moving branch is not, and
an EVM-version bump upstream is exactly the kind of change that should be a deliberate decision on
our side rather than something inherited.
