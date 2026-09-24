# Croom derivation spec — 3. Derivation

## 3.1 The beacon output

For drand round `r`, the beacon output is

```
beaconOutput(r) = sha256(signature(r))        // 32 bytes
```

where `signature(r)` is the 64-byte uncompressed G1 signature the beacon publishes. This is drand's
own definition of a round's randomness, and the definition `EvmnetRegistry` uses. It is chosen over
the raw signature precisely because it is *theirs*: anyone recomputing a Room's history from
`api.drand.sh` arrives at the same value without knowing any Croom convention.

The v2 API does not return a `randomness` field for evmnet, so consumers compute it. A conformance
test pins this against the committed fixtures.

`sha256` costs 60 + 12 × words, measured unchanged from Ethereum on Monad — about 84 gas for 64
bytes (`bench/precompiles.md`). It is paid once per tick that is ever re-executed on chain, which
is only ever a disputed one.

## 3.2 The entropy stream

Each tick draws from a stream seeded by the Room, the round and the beacon:

```
seed      = keccak256(abi.encodePacked(roomId, uint64(round), beaconOutput))
word(i)   = keccak256(abi.encodePacked(seed, uint8(i)))              // i = 0, 1, 2, …
```

Binding `roomId` into the seed means two Rooms sharing a model and a round draw independent streams.
Without it, every Room with the same parameters would move identically, which is both uninteresting
and an obvious way to game one Room by watching another.

A uniform signed draw in `[-1, 1]`:

```
draw(i)   = int256(uint256(word(i)) % uint256(2 × ONE + 1)) - ONE      // ∈ [-ONE, ONE]
drawRaw(i)= uint256(word(i))
```

> **On modulo bias.** `2 × ONE + 1 ≈ 2^61`, so reducing a 256-bit word introduces a bias of order
> `2^-195`. It is far below any threshold that matters, and — more to the point — it is
> **deterministic**. Every implementation reproduces the same bias, so bit-exactness is untouched.
> Rejection sampling would be more uniform and would introduce a data-dependent loop into a function
> that must be re-executable on chain at a bounded cost. The bias stays.

## 3.3 The tick function

```
tick(spec, tickIndex, price) -> price'
```

where `round = startRound + tickIndex × tickInterval` and the beacon output for that round is an
input. The function is **pure**: no storage, no timestamps, no block data, no chain state.

It is **recursive** — `price'` depends on `price`, which depends on the tick before it. A Room is a
path, not a lookup table; without path dependence there is no trend, no momentum and nothing worth
taking a position on. The cost of that choice is that computing tick `n` naively means computing all
`n` before it, which is exactly what the commitment ladder exists to avoid: the bisection narrows a
dispute to one tick, and the terminal step re-executes **only that tick** against the prior state
its opponent committed to.

## 3.4 Model 1 — GBM-lite (`model = 1`)

A multiplicative random walk with drift. No transcendental functions: `exp` and `ln` are where two
independent implementations diverge, and this model reaches the same shape with `mul` and `div`
alone.

```
z      = draw(0)
delta  = (vol × z) / ONE
factor = ONE + drift + delta
price' = clamp((price × factor) / ONE)
```

**V9:** `paramA == 0` and `paramB == 0`.

By V7, `factor ∈ (0, 2 × ONE)`, so the price is strictly positive and cannot more than double in a
tick.

## 3.5 Model 2 — mean-reverting (`model = 2`)

`paramA` is the reversion rate `theta`; `paramB` is the anchor the price is pulled toward.

```
z      = draw(0)
pull   = (paramA × (paramB - price)) / ONE
drift' = (drift × price) / ONE
shock  = ((vol × z) / ONE × price) / ONE
price' = clamp(price + pull + drift' + shock)
```

**Note the association in `shock`:** `((vol × z) / ONE × price) / ONE`, two truncations, in that
order. `(vol × z × price) / (ONE × ONE)` is a different number and is wrong.

**V9:** `0 ≤ paramA ≤ ONE` and `minPrice ≤ paramB ≤ maxPrice`.

Addition is exact, so the order of the three summed terms does not affect the result; they are
written left to right for readability, and implementations may not reorder the *divisions*.

## 3.6 Model 3 — jump (`model = 3`)

`paramA` is the per-tick jump probability; `paramB` is the jump magnitude.

```
z      = draw(0)
u      = drawRaw(1)
jump   = (u % uint256(ONE)) < uint256(paramA)
delta  = (vol × z) / ONE
if jump:
    delta = delta + (z >= 0 ? paramB : -paramB)
factor = ONE + drift + delta
price' = clamp((price × factor) / ONE)
```

The jump takes the sign of the same `z` that drives the ordinary move, so a jump amplifies the tick
it lands on rather than fighting it. A jump on `z == 0` is upward by definition of `z >= 0`; this is
a deliberate tie-break, not an accident, and it happens with probability `2^-61`.

**V9:** `0 ≤ paramA ≤ ONE` and `paramB ≥ 0`. V7 counts `abs(paramB)` in `modelExtra`, which is what
keeps `factor` positive when a jump lands against the drift.

## 3.7 Clamping

```
clamp(x) = x < minPrice ? minPrice : (x > maxPrice ? maxPrice : x)
```

With V4–V7 satisfied the clamp is a **safety net, not a mechanism**: a well-formed Room reaches it
only by drifting there over many ticks, never by one tick jumping out of range. A Room whose clamp
binds frequently is badly parameterised, and that is the author's choice to make — the protocol does
not second-guess it.

The clamp is applied once, after the model, and never to intermediates.

## 3.8 Commitments

Leaves and internal nodes are domain-separated so that no internal node can ever be presented as a
leaf:

```
leafHash(tickIndex, round, price) = keccak256(abi.encodePacked(
    uint8(0x00), uint64(tickIndex), uint64(round), int256(price)))

nodeHash(left, right)             = keccak256(abi.encodePacked(
    uint8(0x01), bytes32(left), bytes32(right)))

stateHash(roomId, tickIndex, price) = keccak256(abi.encodePacked(
    uint8(0x02), bytes32(roomId), uint64(tickIndex), int256(price)))
```

`tickIndex` is bound into the leaf as well as being its position in the tree. That is redundant, and
deliberately so: it means a proof cannot be replayed at a different index even if a tree is
malformed.
