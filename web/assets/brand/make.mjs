// Builds the Croom mark from a real derived price path.
//
// The squiggle is not decorative and not drawn by hand: it is 240 closes of Room
// 0x29bcf64c, derived in the browser from drand beacon rounds by the same specification the
// contracts implement, then normalised. The logo is an actual Croom price series.
import { Resvg } from "@resvg/resvg-js";
import { readFileSync, writeFileSync } from "node:fs";

const PTS = JSON.parse(readFileSync(new URL("./points.json", import.meta.url), "utf8"));

const INK = "#09090b";
const ACCENT = "#8b7cff";
const TEXT = "#ededf0";
const RULE = "#26262e";

// points.json already holds every 5th close: 240 points at gallery-thumbnail size is mush,
// and 49 still reads as a chart.

function mark({ size, pathBox, stroke, wordmark, caption }) {
  const pts = PTS;
  const [bx, by, bw, bh] = pathBox;
  const d = pts
    .map(([x, y], i) => `${i ? "L" : "M"}${(bx + x * bw).toFixed(1)},${(by + y * bh).toFixed(1)}`)
    .join("");

  const [w, h] = size;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
  <rect width="${w}" height="${h}" fill="${INK}"/>
  <rect x="${wordmark.inset}" y="${wordmark.inset}" width="${w - wordmark.inset * 2}" height="${h - wordmark.inset * 2}"
        fill="none" stroke="${RULE}" stroke-width="${wordmark.frame}"/>
  <path d="${d}" fill="none" stroke="${ACCENT}" stroke-width="${stroke}"
        stroke-linejoin="round" stroke-linecap="round"/>
  <text x="${w / 2}" y="${wordmark.y}" fill="${TEXT}" font-family="Chakra Petch" font-weight="700"
        font-size="${wordmark.size}" letter-spacing="${wordmark.tracking}" text-anchor="middle">CROOM</text>
  ${
    caption
      ? `<text x="${w / 2}" y="${caption.y}" fill="${ACCENT}" font-family="JetBrains Mono" font-weight="700"
        font-size="${caption.size}" letter-spacing="${caption.tracking}" text-anchor="middle">${caption.text}</text>`
      : ""
  }
</svg>`;
}

const render = (svg, name, width) => {
  const png = new Resvg(svg, {
    fitTo: { mode: "width", value: width },
    font: {
      fontFiles: [
        new URL("./ChakraPetch-Bold.ttf", import.meta.url).pathname,
        new URL("./JetBrainsMono-Bold.ttf", import.meta.url).pathname,
      ],
      loadSystemFonts: false,
      defaultFontFamily: "Chakra Petch",
    },
  })
    .render()
    .asPng();
  writeFileSync(new URL(`./${name}`, import.meta.url), png);
  console.log(`${name.padEnd(22)} ${width}px  ${(png.length / 1024).toFixed(0)} KB`);
};

// Square, for the gallery tile.
render(
  mark({
    size: [1000, 1000],
    pathBox: [130, 232, 740, 300],
    stroke: 16,
    wordmark: { y: 722, size: 164, tracking: 10, inset: 44, frame: 3 },
    caption: { y: 792, size: 25, tracking: 7, text: "DERIVED, NOT REPORTED" },
  }),
  "croom-logo-square.png",
  1000,
);

// Wide, for a banner slot.
render(
  mark({
    size: [1600, 900],
    pathBox: [200, 196, 1200, 280],
    stroke: 15,
    wordmark: { y: 652, size: 170, tracking: 12, inset: 40, frame: 3 },
    caption: { y: 722, size: 26, tracking: 8, text: "DERIVED, NOT REPORTED" },
  }),
  "croom-logo-wide.png",
  1600,
);

// The size a gallery actually shows it at.
render(
  mark({
    size: [1000, 1000],
    pathBox: [130, 232, 740, 300],
    stroke: 16,
    wordmark: { y: 722, size: 164, tracking: 10, inset: 44, frame: 3 },
    caption: { y: 792, size: 25, tracking: 7, text: "DERIVED, NOT REPORTED" },
  }),
  "thumb-check.png",
  128,
);
