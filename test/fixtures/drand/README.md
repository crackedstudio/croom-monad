# drand evmnet fixtures

**Fetched 2026-09-23** from `https://api.drand.sh/v2/chains/04f1e906…/`.

`info.json` is the beacon's own description of itself, and the rounds are real signatures from the
League of Entropy. They are committed rather than fetched at test time so the suite is deterministic
and runs offline — and so that a change to the beacon's parameters shows up as a failing test with a
diff, instead of as silently different behaviour.

PLAN.md §3.1 states the chain hash from memory of the design. This directory is the check on that
claim, which is why step 2.1 exists at all: the hash was confirmed against the live API *before*
anything hardcoded it. It matched.

| | |
| --- | --- |
| Beacon ID | `evmnet` |
| Chain hash | `04f1e9062b8a81f848fded9c12306733282b2727ecced50032187751166ec8c3` |
| Scheme | `bls-bn254-unchained-on-g1` |
| Period | 3 s |
| Genesis | 1727521075 |
| Public key | 128 bytes — **uncompressed** G2 |
| Signature | 64 bytes — **uncompressed** G1 |

Rounds committed: 1, 2, 1000, 1000000, 20880731, 20880831. First rounds, a round far from genesis,
and two recent ones — the cases where an off-by-one in round encoding would show up.

## Why uncompressed matters

Both the key and the signatures arrive as raw affine coordinates, so nothing on-chain has to
decompress a point. Decompression needs a modular square root, which on Monad would mean `modexp`
or a scalar multiplication at 30,000 gas (`bench/precompiles.md`). Getting this for free was luck,
not design — but it is the difference between a verifier that costs a pairing and one that costs a
pairing plus a square root.

## Unchained

The scheme is `unchained`: the signed message is the round number alone, with no dependency on the
previous round's signature. Any round can therefore be verified in isolation, which is what makes a
sparse proven floor possible — we never have to walk a chain of predecessors to prove that round
*r* exists.
