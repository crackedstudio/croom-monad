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

Fonts are loaded from `public/` rather than from Google Fonts: the network fetch stalls
`delayRender()` in the render browser, and these are the same files the logo was rasterised with.

Colours come from `../web/assets/croom.css` via `src/theme.ts`.

**The end card has a placeholder URL.** `src/Ad.tsx` has `const url = "croom.pages.dev"` — set it to
the real deployment and re-render.
