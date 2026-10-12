# Brand assets

`croom-logo-square.png` (1000×1000) and `croom-logo-wide.png` (1600×900).

The line in the mark is not decoration and was not drawn by hand. It is **49 real closes from Room
`0x29bcf64c`**, every fifth round of the first 240, derived in the browser from drand beacon rounds
by the same specification the contracts implement, then normalised to the unit square. The logo is
an actual Croom price series — which is the only thing a logo for this project ought to be.

Regenerate:

```bash
npm i @resvg/resvg-js
node make.mjs
```

`points.json` holds the normalised path. To re-derive it, open the app, let the chart finish, and
read the closes back out of the rendered series rather than inventing a shape.

Colours and type come from `../croom.css`: ink `#09090b`, accent `#8b7cff`, text `#ededf0`,
Chakra Petch for the wordmark, JetBrains Mono for the caption.
