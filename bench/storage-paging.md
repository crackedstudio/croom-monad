# Storage paging — measured on Monad

**Measured 2026-09-23** against `StoragePageProbe` at
[`0xc33056Af574168157a7D801Ab213cf1d4416dDc6`](https://testnet.monadscan.com/address/0xc33056Af574168157a7D801Ab213cf1d4416dDc6),
deployed at block 65024223. Both measurement functions are reachable by `eth_call`, so only the
deployment cost anything.

```bash
make measure-storage PROBE=0xc33056Af574168157a7D801Ab213cf1d4416dDc6
```

## The page boundary is exactly where the docs say

`measureSloads()` reads slots 0, 1, 127, 128, 200 in one call:

| Slot | Gas | Reading |
| --- | --- | --- |
| 0 | **8,105** | first touch of page 0 — cold |
| 1 | 105 | same page — warm |
| 127 | 105 | **still page 0** — warm |
| 128 | **8,105** | **new page** — cold again |
| 200 | 105 | same page as 128 — warm |

Pages are exactly 128 slots and begin at multiples of 128. Cold costs 8,100 and warm costs 100
(the extra 5 is harness overhead). **A cold page touch is 81× a warm one.**

## The write model, derived from measurement

`measureSstores()` writes slot 300 (new, new page), 301 (new, page now warm), 1 (existing, page 0
cold), then 2 (new, page 0 warm):

| Write | Gas | Decomposition |
| --- | --- | --- |
| new slot, cold page | **27,908** | 100 base + 8,000 page load + 2,800 page write + 17,000 growth |
| new slot, warm page | **17,108** | 100 base + 17,000 growth |
| existing slot, cold page | **10,908** | 100 base + 8,000 page load + 2,800 page write |
| new slot, warm page | **17,108** | 100 base + 17,000 growth |

Every row fits `100 + 8,000·(first touch of page) + 2,800·(first write to page) + 17,000·(slot was
previously unset)` to within the 8 gas of harness overhead. Page load and page write are each
charged **once per page per transaction**, not per slot.

The documented "17,000 per new high-water mark" is better read as **per previously-unset slot**:
slot 2 sits far below the highest slot ever written (300) and was still charged the full 17,000.

## Two consequences for the ladder

**1. Contiguity is worth 8,000 gas per page avoided (step 4.3).**
A checkpoint that touches proven floor, last finalised epoch and open-challenge pointer pays 8,000
once if they share a page and 24,000 if they are scattered across three. On Ethereum the same
mistake costs 2,100 per slot and is a rounding error; here it is most of the operation. Slot
assignment for each Room's hot state is a deliberate layout decision, written down and asserted by
a test — not whatever order the fields happen to be declared in.

**2. Reuse beats growth by 170× (step 5.1).**
Writing a previously-unset slot costs 17,000. Overwriting a set slot in an already-warm page costs
**100**. A ladder that appends checkpoint records forever pays the growth charge on every epoch, in
perpetuity. A fixed-size ring buffer over finalised epochs pays it once per slot and then never
again.

This is not a micro-optimisation — it changes what the contract should store. The chain does not
need every historical checkpoint in state: it needs the commitments still inside the challenge
window, plus the last finalised root. Everything older is reconstructible from events and from the
beacon, which is the entire premise of the project. **The storage schedule is pushing us toward the
architecture the design already wanted**, and the number says how much that choice is worth.

Both points get measured again once `Ladder` exists, against the real access pattern rather than a
probe.
