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

Composed, not sourced. `synth.py` is a wavetable synthesiser and `make-audio.py` is the score;
between them they need nothing beyond the standard library, so there are no samples and no licences
to worry about on a submission whose whole argument is "check it yourself".

```bash
python3 make-audio.py     # ~4s -> public/soundtrack.wav
```

**160 BPM in A minor, and the tempo is chosen rather than guessed.** A bar is exactly 1.5 seconds,
so drand's three-second period is two bars and the beacon lands on the downbeat. Every cut in the
video sits on a bar line and the refusal sits on a beat, so the track and the edit agree without
either being bent to fit the other.

| bars | section | |
| --- | --- | --- |
| 0–3 | intro | arpeggio and hats |
| 4–6 | build | bass and kick arrive |
| 7–9 | beacon | full groove, the pulse foregrounded while it is being explained |
| 10–11 | tension | stripped back over a riser |
| 12 | **the hit** | everything stops for the refusal, then the beat returns heavier |
| 15–17 | payout | lead an octave up, bells, resolving brighter |
| 18–19 | outro | the last chord left ringing |

The refusal at 18.0s is the loudest moment by a wide margin, with a near-silent gap in front of it
so it lands. A `tanh` limiter keeps it from crackling.

Additive synthesis was tried first and was far too slow — a band-limited saw is a dozen sine calls
per sample, and at 48kHz across thirty seconds of polyphony that is hundreds of millions of them.
Each waveform is now built once into a 2048-point table and played back by a phase accumulator,
which renders the whole track in about four seconds.

Fonts are loaded from `public/` rather than from Google Fonts: the network fetch stalls
`delayRender()` in the render browser, and these are the same files the logo was rasterised with.

Colours come from `../web/assets/croom.css` via `src/theme.ts`.

**The end card has a placeholder URL.** `src/Ad.tsx` has `const url = "croom.pages.dev"` — set it to
the real deployment and re-render.
