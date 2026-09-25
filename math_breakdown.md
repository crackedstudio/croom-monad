# The mathematics of Croom, from the ground up

Everything here assumes basic algebra — rearranging equations, powers, square roots — and nothing
else. Where a new idea is needed, it gets built before it gets used.

Every number quoted is produced by the actual implementation and asserted in
[`test/WorkedExample.t.sol`](test/WorkedExample.t.sol), so if the code changes and this document
stops being true, a test fails and says which line.

---

## 1. The problem

We want a price chart. Not of anything real — a made-up asset that wiggles like a market. Three
requirements, and they fight each other:

1. **Unpredictable.** Nobody should be able to guess the next move, including whoever created it.
2. **Verifiable.** Anyone should be able to recompute the whole history and get *exactly* the same chart.
3. **Realistic.** It should behave like a price, not like static.

(1) and (2) sound contradictory. The resolution is that the chart is a **deterministic function of
public randomness**. A global lottery (drand) publishes an unpredictable number every 3 seconds.
Once published it is public forever. So the price is unguessable *before* the draw and reproducible
by anyone *after* it.

That turns the whole problem into: **given a stream of random numbers, compute a realistic price
path — identically, on every machine, forever.**

The rest of this document is how.

---

## 2. Why integers, and only integers

The obvious way to store a price like `100.25` is a decimal number. Computers use *floating point*
for that, and floating point is not exact. The classic demonstration, true in almost every
programming language:

```
0.1 + 0.2 = 0.30000000000000004
```

Not a bug — `0.1` has no exact binary representation, like `1/3` has no exact decimal one. The error
is tiny, but it depends on the order of operations and can differ between processors and compilers.

For us, tiny is fatal. Two people recomputing the same chart must agree on **every digit**, or the
whole claim collapses. So there is no floating point anywhere. Instead:

> **A price is a whole number of hundred-quintillionths.**

We pick a scale, `WAD = 10^18`, and store every value multiplied by it.

| Real value | Stored as |
|---|---|
| 1.0 | 1000000000000000000 |
| 100.25 | 100250000000000000000 |
| 0.5 | 500000000000000000 |

All arithmetic is then integer arithmetic, which is exact and identical everywhere.

**Multiplication needs care.** If `a` and `b` are both scaled by 10^18, then `a × b` is scaled by
10^36 — too big by a factor of 10^18. So the scaled multiply is:

```
mulWad(a, b) = a × b / WAD
```

and the scaled divide puts the factor back:

```
divWad(a, b) = a × WAD / b
```

That single extra division is where the next problem comes from.

---

## 3. Rounding: the direction matters more than the amount

`a × b / WAD` almost never divides evenly. Something must be thrown away. The rule we use is
**truncate toward zero** — just delete the leftover, whichever side of zero you are on:

```
 7 / 2  =  3        -7 / 2  = -3
```

Note that `-7 / 2` is `-3` and not `-4`. That is *toward zero*, not *downward*. The distinction has
no effect on positive numbers, which is exactly why it is dangerous: a test suite using only
positive prices passes either way.

Two places this bites, both real:

**Python disagrees.** Python's `//` rounds *downward*, so `-7 // 2` is `-4`. A tool written in
Python to generate expected answers would disagree with the contract on every negative
intermediate — and only on negative ones.

**The order of operations changes the answer.** Because each division discards a remainder:

```
(a × b / WAD) × c / WAD        ≠        a × b × c / (WAD × WAD)
```

These differ by at most one unit in the last place — 10^-18 of a price. That is enough to produce a
different summary hash, which is enough to lose a dispute you were right about. So the specification
writes every formula with explicit brackets, and implementations copy the brackets literally.

**One place needs the other rounding.** The exponential function (§8) reduces its argument using
`⌊x / ln2⌋` — a genuine *downward* round, and its input is negative half the time. Getting that one
wrong lands on the wrong power of two and produces an answer wrong by a factor of two. It has its
own helper and its own test.

---

## 4. From a hash to a bell curve

### 4.1 Getting a uniform number

The beacon gives us 32 random-looking bytes. We hash them together with the Room's identity and a
label, and take the **first 8 bytes** of the result as a number between `0` and `2^64 − 1`. Dividing
by `2^64` gives a number between 0 and 1:

```
U = (first 8 bytes of the hash) × WAD / 2^64
```

Every value in that range is equally likely. That is a **uniform** draw — a flat distribution.

### 4.2 Why flat is wrong

If prices moved by a flat random amount, a huge move would be exactly as likely as a tiny one. Real
prices do not behave like that. Small moves are common, large moves are rare, and enormous moves are
very rare. That shape is the **normal distribution** — the bell curve.

So we need to bend a flat draw into a bell-shaped one.

### 4.3 The trick

Here is the idea, and it is genuinely clever. Suppose you have a curve and you want random numbers
that follow it. Write down `Φ(x)` = *the probability that a bell-curve draw comes out below `x`*.
This is a function that climbs from 0 to 1 as `x` goes from very negative to very positive:

| x | Φ(x) |
|---|---|
| −2 | 0.023 |
| −1 | 0.159 |
| 0 | 0.500 |
| +1 | 0.841 |
| +2 | 0.977 |

Now **run it backwards**. Feed it a flat random number between 0 and 1, and ask: *which `x` would
have given this probability?* That function is `Φ⁻¹`, the inverse.

Do this with flat draws and the answers come out bell-curve distributed. It works for any
distribution, and the reason is almost a tautology: **a value lands below `x` exactly when the flat
draw lands below `Φ(x)`** — which happens with probability `Φ(x)`, which is what we wanted.

Flat draws near 0.5 map to small numbers; the rare draws near 0 or 1 map to the extremes. The
flatness is stretched at the edges and squashed in the middle, and out comes a bell.

### 4.4 Computing it

There is no tidy formula for `Φ⁻¹`. We use a published approximation — **Wichura's algorithm
AS241**, from 1988 — which is a ratio of two polynomials, with different coefficients in three
regions: the middle, the tails, and the far tails. 48 constants in total, and they are *data*: a
single mistyped digit leaves the middle looking perfectly sensible and corrupts only the extremes.

Our implementation, against values published to sixteen decimal places:

| p | Φ⁻¹(p), ours | published |
|---|---|---|
| 0.10 | −1.281551565544600443 | −1.2815515655446004 |
| 0.30 | −0.524400512708040796 | −0.5244005127080409 |
| 0.60 | +0.253347103135799810 | +0.2533471031357997 |
| 0.99 | +2.326347874040841086 | +2.3263478740408408 |

We call the result **`Z`**. It is the tick's "shock": usually between −1 and +1, occasionally
beyond ±2, very rarely beyond ±4.

---

## 5. Volatility, and why time enters as a square root

Volatility, written `σ` ("sigma"), is how much a price typically moves. It is quoted **per year** —
"75% volatility" is a fast, jumpy market.

Our ticks are 3 seconds apart. How much should a price move in 3 seconds if it moves 75% in a year?

The tempting answer is to divide by the number of rounds in a year. **That is wrong**, and the
reason is worth understanding.

Imagine flipping a coin 100 times, scoring +1 for heads and −1 for tails. How far from zero do you
typically end up? Not 100 — the ups and downs cancel. Not 1 either. The answer is about **10**,
which is `√100`.

This is the general rule: when you add up independent random moves, their **squared** sizes add, not
their sizes. So the typical total grows like the square root of the number of steps.

Reading it backwards gives what we need: to go from a year to one round, **divide by the square root
of the number of rounds**, not by the number itself.

There are `31,536,000 / 3 = 10,512,000` rounds in a year. And `√10,512,000 ≈ 3242.2`. So:

```
σ_round = 0.75 / 3242.2 ≈ 0.000231  =  0.0231% per round
```

The implementation computes this as `σ × √dt`, where `dt` is one round expressed in years:

| Quantity | Value (scaled by 10^18) | Meaning |
|---|---|---|
| `dt` | 95129375951 | one round = 0.000000095 years |
| `√dt` | 308430504248525 | 0.00030843 |
| `σ_t` at 75% a year | 231322878186393 | **0.0231% per round** |

Sanity check on the square root: 0.00030843² ≈ 0.0000000951, which is `dt`. ✓

---

## 6. The price rule

Prices move **multiplicatively**, not additively. A £1 move matters enormously at a price of £2 and
not at all at £10,000. What stays comparable across price levels is the *percentage* move.

The clean way to handle multiplication is logarithms. A reminder of the one property that matters:

```
ln(a × b) = ln(a) + ln(b)
```

Logarithms turn multiplying into adding. So instead of multiplying the price by a random factor, we
**add** a random amount to the price's logarithm, then convert back:

```
next price = exp( ln(price)  −  correction  +  σ_t × Z )
```

Three pieces: where we were, a correction explained in §7, and the shock.

### A complete tick

Price 100, volatility 75% a year, and the beacon happens to produce `U = 0.6`:

| Step | Value |
|---|---|
| `Z = Φ⁻¹(0.6)` | 0.253347103135799810 |
| `σ_t × Z` | 0.0000586 |
| correction | 0.0000000268 |
| `ln(100)` | 4.605170185988091354 |
| sum | 4.605228765... |
| `exp(sum)` | **100.005857994167833280** |

A move of +0.0059%. An above-average draw, a small move up. Repeat every 3 seconds, forever.

---

## 7. The correction term, which is the subtle part

Why subtract anything at all? The shock `Z` is symmetric — as likely to be +0.5 as −0.5. Surely the
price is already fair?

It is not, and here is the algebra.

Adding `+s` to the logarithm multiplies the price by `u = exp(s)`. Adding `−s` multiplies it by
`exp(−s) = 1/u`. So a symmetric move in logarithm-land is a multiply by `u` or by `1/u`, each with
equal chance. The average multiplier is:

```
(u + 1/u) / 2
```

Try `u = 1.1`: `(1.1 + 0.9091) / 2 = 1.00454`. **Bigger than 1.** Try `u = 1.5`:
`(1.5 + 0.6667) / 2 = 1.0833`. Bigger again.

It is always bigger than 1, and you can prove it with school algebra. Since `(√u − 1/√u)² ≥ 0`,
expand:

```
u − 2 + 1/u ≥ 0     ⟹     u + 1/u ≥ 2     ⟹     (u + 1/u)/2 ≥ 1
```

with equality only when `u = 1`.

So a price driven by a perfectly symmetric shock **drifts upward on average**, forever, for free.
That is not a market; it is a money printer, and anyone betting "up" would win in the long run
without taking a view.

The fix is to subtract exactly enough to cancel it. The amount turns out to be **half the variance**
— `σ_t² / 2` — which is why the formula carries a `−σ_t²/2`. With it, the average multiplier is
exactly 1: the price is as likely to be above as below where it started, weighted properly. That
property is called being a **martingale**, and it is what makes a market on this fair rather than
tilted.

In our numbers `σ_t² / 2 = 0.0000000268` — a rounding error next to the 0.0059% move. Utterly
negligible per tick, and over 10.5 million ticks a year it is the difference between a fair market
and a rigged one. [`test_TheCorrectionKeepsTheAverageFlat`](test/WorkedExample.t.sol) checks that
including it brings the average multiplier closer to 1 than leaving it out.

---

## 8. Computing `exp` and `ln` with whole numbers

`exp` and `ln` are the two functions above that are not plain arithmetic. There is no exact integer
formula for either, so both are built the same way: **shrink the input to a range where a simple
series converges fast, then correct for the shrinking.**

### exp

Use `exp(x) = exp(r) × 2^k`, where `x = k × ln2 + r` and `r` is the leftover, always between 0 and
`ln2 ≈ 0.693`.

- Find `k` by dividing `x` by `ln2` and rounding **down** (this is the floor from §3).
- On the small leftover `r`, use the series `exp(r) = 1 + r + r²/2 + r³/6 + …`, 20 terms. Since `r < 0.7`, the terms shrink fast and 20 is far more than enough.
- Multiply by `2^k`, which for integers is just a bit shift.

### ln

The mirror image. Write `x = m × 2^k` with `m` between 1 and 2, so
`ln(x) = ln(m) + k × ln2`. Finding `k` is just asking how many binary digits `x` has.

For `ln(m)` with `m` close to 1, substitute `y = (m − 1) / (m + 1)`, which is small, and use

```
ln(m) = 2 × (y + y³/3 + y⁵/5 + y⁷/9 + …)
```

19 terms. Because `y < 1/3`, each term is at least 9 times smaller than the last, so the tail is far
below the last digit we keep.

Both are pure integer arithmetic, every rounding defined, every loop a fixed length. No branch
depends on anything secret and nothing can loop forever.

---

## 9. The other two price shapes

The bell-curve walk above is the **Drift** family. Two more ship, and both are simpler.

### Step

Move up or down by a fixed amount, each with probability one half:

```
U < 0.5  →  price + s
otherwise →  price − s
```

Blocky and readable — a staircase. Fair by inspection: equal chances, equal sizes. No logarithms
involved. It is also the one that cannot go subtly wrong, which makes it a useful control: if Step
diverges between two implementations, the bug is in the plumbing, not the mathematics.

### Spike

Long quiet stretches, then a sudden jump. Most ticks drift gently one way; rarely, the price leaps
the other.

Say a spike happens with probability `q` — one round in `N`, so `q = 1/N` — and multiplies the price
by `(1 + S)`. On every other tick the price is multiplied by `(1 − d)`, a slow bleed the other way.

**How big must the bleed be for the game to stay fair?** Set the average multiplier to exactly 1:

```
q(1 + S) + (1 − q)(1 − d) = 1
```

Expand:

```
q + qS + 1 − d − q + qd = 1
qS − d + qd = 0
d(1 − q) = qS
d = qS / (1 − q)
```

That is the whole derivation — rearranging one equation. With `N = 500` (a spike every 25 minutes)
and an average spike of 1%, the bleed is about `0.002%` per tick. The spikes exactly pay for the
drift.

**Spikes are never "due."** Each tick's chance is the same `1/N` regardless of how long it has been
quiet. Twenty minutes of calm tells you nothing about the next tick — the same way a coin that has
landed heads five times is still a fair coin. The interface says so out loud.

---

## 10. Committing to a price history in 32 bytes

The chain does not store prices. It stores a **fingerprint** of a batch of them — typically 100
rounds, five minutes — and it is built like a knockout tournament:

- Hash each round's data. That is the bottom row.
- Hash them in pairs to make the next row up. Then pairs of those. Keep going.
- After about 7 doublings, 100 entries become **one** 32-byte value: the *root*.

This is a **Merkle tree**, and it has the property that makes everything else possible: to prove one
particular price belongs to a root, you don't need the other 99. You need the 7 hashes along the path
up the tree. Anyone can recompute the root from your price plus those 7 values and check it matches.

So: 100 prices, committed in 32 bytes, with a 7-hash proof for any single one of them. The
logarithm again — `log₂(100) ≈ 7`.

That same logarithm is why disputes are cheap. When someone challenges a batch, the two sides play
a guessing game: *do we disagree in the first half or the second?* Each answer halves the range, so
**7 rounds of questions** isolate the single tick they disagree about. Only that one tick is then
recomputed on-chain, by the contract, from the beacon. Whoever was wrong loses their deposit.

---

## 11. Why all this exactness

Every rounding rule, every bracket, every loop bound — it all exists to serve one sentence:

> The contract must be able to declare a claimed price **wrong**, not *approximately different*.

If two honest implementations could disagree by one unit in the last place, then a liar could always
claim to be an honest implementation that rounded differently, and the fraud proof would have
nothing to bite on. There would be no way to settle a dispute, so there would be no way to trust an
uncontested batch either, so the chain would have to verify everything itself — which costs about
1,600 MON a day at current prices and is therefore not an option.

**Exactness is not tidiness here. It is the entire security model.** That is why the maths is pinned
to the last digit, why there are 7,253 test cases for the arithmetic alone before a single price is
computed, and why they are checked against an implementation in a different language that was
written first and frozen.

---

## Where to look next

| | |
|---|---|
| The normative specification | [`reference/croom-core/docs/core-v1.md`](reference/croom-core/docs/core-v1.md) |
| Fixed point, `exp`, `ln` | [`src/FixedPointMath.sol`](src/FixedPointMath.sol) |
| The inverse normal, AS241 | [`src/InverseNormal.sol`](src/InverseNormal.sol) |
| Every number in this document | [`test/WorkedExample.t.sol`](test/WorkedExample.t.sol) |
| The 7,253 arithmetic cases | [`test/FixedPointMath.t.sol`](test/FixedPointMath.t.sol) |
| Why Solidity makes this harder than Rust | [`docs/porting-notes.md`](docs/porting-notes.md) |
