# Croom derivation spec — 4. Conformance vectors

## 4.1 What a vector is

A vector is a Room, a starting price, a run of beacon outputs, and the exact price after every tick.
An implementation conforms if it reproduces every price **bit for bit**. Not within a tolerance —
there is no tolerance, because every operation here is exact integer arithmetic and a one-unit
difference is a different Merkle root.

## 4.2 Packed format (`.bin`)

Foundry parses JSON slowly enough that a large suite stops being run, so the fast path reads a
packed fixture instead. All integers are big-endian; signed values are two's complement.

```
header      magic       8 bytes    "CROOMVEC"
            version     1 byte     0x01
            specVersion 1 byte     matches spec.version
            recordCount 4 bytes    uint32

record      spec        238 bytes  encodeSpec(), §2.3
            firstTick   8 bytes    uint64, tick index of the first tick in this run
            tickCount   4 bytes    uint32
            priceBefore 32 bytes   int256, the price entering firstTick
            beacon[]    32 × tickCount bytes   beaconOutput for each tick, in order
            price[]     32 × tickCount bytes   expected price after each tick
```

Records are concatenated with no padding. A reader that has consumed `recordCount` records must be
exactly at end of file; anything else means a truncated or corrupt fixture and is a hard failure,
never a partial pass.

`priceBefore` is carried explicitly rather than recomputed from `initialPrice`, so a vector can
start mid-history and exercise a tick 400,000 deep without the fixture containing the 400,000 ticks
before it. That is also what lets the adversarial suite build a vector around one specific disputed
tick.

## 4.3 Full format (`.json`)

The nightly sweep and the TypeScript differential use JSON, where readability beats parse speed.
Every integer is a **decimal string**, never a JSON number: `JSON.parse` yields a `double`, and a
`double` cannot hold 18 significant decimals.

```json
{
  "specVersion": 1,
  "roomId": "0x…",
  "spec": { "version": 1, "model": 1, "startRound": "20880831", "…": "…" },
  "firstTick": "0",
  "priceBefore": "1000000000000000000",
  "ticks": [
    { "tickIndex": "0", "round": "20880831",
      "beaconOutput": "0x…", "price": "1003217880000000000" }
  ]
}
```

## 4.4 Coverage the suite must contain

| Case | Why |
| --- | --- |
| Every model, ordinary parameters | the baseline |
| `drift` positive, negative, zero | the sign of every truncation flips with it |
| `vol == 0` | a deterministic Room; any divergence here is a pure arithmetic bug with no noise to hide in |
| `vol` at the V7 limit | the multiplier approaches zero and two |
| Price pinned at `minPrice` and at `maxPrice` | the clamp on both sides |
| Prices near `10^6 × ONE` | the widest intermediates, V5 |
| Prices near `minPrice` with many ticks | truncation-driven decay: does the price crawl down and stick? |
| `tickInterval > 1` | round/tick index mapping |
| Jump model: `paramA == 0`, `paramA == ONE` | never jumps, always jumps |
| Jump landing on `z < 0` and `z ≥ 0` | the sign tie-break, §3.6 |
| A run crossing 400,000+ ticks | long-horizon drift of accumulated truncation |

The case that matters most is `vol == 0`. A Room with no volatility has one correct answer per tick
and no plausible-looking wrong answers, so a divergence cannot be argued away as a rounding
difference.

## 4.5 A caveat this project has to state out loud

PLAN.md §6 describes the TypeScript and Solidity implementations as two independent
reimplementations agreeing bit for bit, and treats that agreement as evidence the derivation is
right.

**That evidence is weaker than it sounds here**, because the spec and both implementations are being
written by the same author in the same fortnight. Independent implementations catch *transcription*
errors — a wrong constant, a flipped sign, a reassociated expression. They do not catch a
misunderstanding shared by both, because the same misunderstanding produced both.

What the differential test genuinely buys us:

- Any place the two disagree is a place **this spec is ambiguous**, which is worth finding on day 4 rather than day 19.
- It protects the derivation against later drift, when one side is changed and the other is not.

What it does not buy us is proof that the spec says what we meant. The honest claim for the
submission is "two implementations, written from a written spec, agree bit-for-bit on N vectors",
and not "independently verified". The difference matters to anyone reading carefully, and the sort
of judge worth impressing reads carefully.
