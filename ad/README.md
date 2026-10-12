# The 30-second product advertisement

```bash
npm install
npm run studio     # preview and scrub
npm run render     # out/croom-ad.mp4
```

Two things in here are real on purpose, because the protocol is about not fabricating numbers and
an advert for it should not fabricate its own:

- **The price line** is `src/points.json` — 49 closes from Room `0x29bcf64c`, derived from drand
  beacon rounds by the specification the contracts implement, read out of the running app.
- **The refusal** is what the deployed `Ladder` actually returns. `99.999827` is the honest close it
  accepts at round 21,193,065, and `LeafNotCommitted(21193065)` is the error for a price that is not
  in the committed batch.

## The soundtrack

`make-audio.py` synthesises it — no samples, no licences, no dependencies beyond the standard
library:

```bash
python3 make-audio.py     # writes public/soundtrack.wav
```

**It pulses every three seconds because drand does.** At 30fps that is one pulse every 90 frames,
landing on the same beats the Beacon scene animates, so the rhythm a viewer feels is the thing the
product is built on rather than a bed chosen to fill silence.

Everything is a sine, a pitch sweep, or shaped noise. The refusal at 18.4s is deliberately the
loudest moment in the piece — about thirteen times the level of the quiet between pulses — because
it is the point of the advert. A `tanh` soft limiter catches it so it hits without crackling.

Fonts are loaded from `public/` rather than from Google Fonts: the network fetch stalls
`delayRender()` in the render browser, and these are the same files the logo was rasterised with.

Colours come from `../web/assets/croom.css` via `src/theme.ts`.

**The end card has a placeholder URL.** `src/Ad.tsx` has `const url = "croom.pages.dev"` — set it to
the real deployment and re-render.
