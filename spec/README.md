# spec — the canonical derivation specification

**This is the authority.** `Tick.sol` and the TypeScript derivation are both measured against these
documents, and where an implementation disagrees with them, the implementation is wrong.

| | |
| --- | --- |
| [`00-arithmetic.md`](00-arithmetic.md) | fixed point, truncation toward zero, association order |
| [`01-room.md`](01-room.md) | the Room spec, its encoding, `roomId`, and creation-time validation |
| [`02-derivation.md`](02-derivation.md) | beacon output, entropy stream, the three price models, commitments |
| [`03-conformance.md`](03-conformance.md) | vector formats and required coverage |

## Status

**Draft, written 2026-09-24.** Written from scratch for this build — there was no prior
specification to import, and no prior implementation to differential-test against.

Amending any of these documents means **regenerating every conformance vector**. That is deliberate
friction: the spec should be hard to change once vectors exist, because a silent change to the spec
is a silent change to every Room ever opened.

## The invariant the whole thing rests on

> `abs(drift) + vol + modelExtra < ONE`

Enforced at Room creation (V7, §2.4). It guarantees every model's per-tick multiplier lies strictly
inside `(0, 2)`, which in turn means no price can reach zero, change sign, or double in a tick. With
it, the tick function is total for every Room the registry will accept, and the clamps are a safety
net rather than part of the model. Without it, every model needs its own case analysis for
degenerate inputs.

## Reading order for an implementer

`00` then `02`. `01` matters when you are building `Registry`, and `03` when you are generating or
consuming vectors. If you read only one section, read [§1.2 and §1.3](00-arithmetic.md) — truncation
direction and association order are where bit-exactness is won or lost, and neither is visible in a
test that only uses positive numbers.
