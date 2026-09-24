# Croom derivation spec — 2. The Room

## 2.1 What a Room is

A Room is an **immutable price process**. Its entire definition is a fixed-width byte string; its
identity is the hash of that string. There is no field an administrator could change, because
changing any field produces a different Room.

```
roomId = keccak256(encodeSpec(spec))
```

The registry stores the `roomId` and emits `encodeSpec(spec)` in an event. The chain never holds the
body, and an indexer reconstructs it from logs. Immutability is structural, not promised.

## 2.2 Spec fields

| # | Field | Type | Meaning |
| --- | --- | --- | --- |
| 0 | `version` | `uint8` | Spec format version. `1` for this document. |
| 1 | `model` | `uint8` | Price model, §3. `1` = GBM-lite, `2` = mean-reverting, `3` = jump. |
| 2 | `startRound` | `uint64` | drand round at which tick 0 is produced. |
| 3 | `tickInterval` | `uint32` | Beacon rounds per tick. `1` = every round (3 s). Must be ≥ 1. |
| 4 | `initialPrice` | `int256` | Price before tick 0. 18 decimals. |
| 5 | `minPrice` | `int256` | Lower clamp, §4.3. |
| 6 | `maxPrice` | `int256` | Upper clamp, §4.3. |
| 7 | `drift` | `int256` | Per-tick drift. 18 decimals, signed. |
| 8 | `vol` | `int256` | Per-tick volatility scale. 18 decimals, non-negative. |
| 9 | `paramA` | `int256` | Model-specific, §3. |
| 10 | `paramB` | `int256` | Model-specific, §3. |

`paramA` and `paramB` are named generically on purpose: a fixed-width spec means every model shares
one encoding, so `Registry` needs no per-model branches and `roomId` is computed identically for
every Room. Each model says what they mean, and validation rejects a Room that leaves a meaningful
parameter unset.

## 2.3 Encoding

```
encodeSpec(spec) = abi.encodePacked(
    version,       // 1 byte
    model,         // 1 byte
    startRound,    // 8 bytes
    tickInterval,  // 4 bytes
    initialPrice,  // 32 bytes
    minPrice,      // 32 bytes
    maxPrice,      // 32 bytes
    drift,         // 32 bytes
    vol,           // 32 bytes
    paramA,        // 32 bytes
    paramB         // 32 bytes
)                  // 238 bytes, fixed
```

Every field is fixed-width, so the encoding is unambiguous and `roomId` is a hash over exactly 238
bytes. Two specs collide only if they are byte-identical, in which case they are the same Room and
opening it twice is a no-op.

## 2.4 Validation at creation

A Room is rejected at creation unless **all** of the following hold. These are what make the tick
function *total* — every well-formed Room ticks forever without a clamp being load-bearing, an
overflow, or a division by zero.

| # | Rule | Why |
| --- | --- | --- |
| V1 | `version == 1` | Unknown versions are not silently reinterpreted. |
| V2 | `model ∈ {1, 2, 3}` | |
| V3 | `tickInterval ≥ 1` | A tick interval of zero has no meaning and divides by zero. |
| V4 | `0 < minPrice ≤ initialPrice ≤ maxPrice` | Prices are strictly positive. A Room that can reach zero is absorbing: truncation pins it there and the market dies silently. |
| V5 | `maxPrice ≤ 10^6 × ONE` | Bounds the widest intermediate to ~10^60, comfortably inside `int256`. |
| V6 | `vol ≥ 0` | Negative volatility would invert the shock's sign, which is a different model wearing a disguise. |
| V7 | `abs(drift) + vol + modelExtra(model) < ONE` | **The central invariant.** It guarantees the per-tick multiplier stays strictly positive, so no price can cross zero or flip sign. `modelExtra` is `abs(paramB)` for the jump model and `0` otherwise. |
| V8 | `startRound ≥ 1` | drand rounds are 1-indexed; round 0 does not exist. |
| V9 | model-specific rules, §3 | |

V7 is the rule that does the real work. With it, every model's multiplier lies in `(0, 2 × ONE)`,
the clamps in §4.3 are a safety net rather than part of the model's behaviour, and no implementation
ever has to decide what a negative price means.

## 2.5 Rounds and ticks

```
roundOf(tickIndex) = startRound + tickIndex × tickInterval
```

Tick indices are 0-based. Tick 0 is the first tick and transforms `initialPrice`; the price *before*
tick 0 is `initialPrice` itself and is not a tick.

A Room has no end. `tickIndex` is bounded in practice by `roundOf` staying inside `uint64`, which at
3 seconds per round is longer than the heat death of anything relevant.
