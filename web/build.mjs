import { createHash } from "node:crypto";
import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { context } from "esbuild";

const envText = readFileSync(new URL("./.env", import.meta.url), "utf8");
const configuredRpc = envText
  .split(/\r?\n/)
  .map((line) => line.match(/^\s*MONAD_TESTNET_RPC\s*=\s*(.*?)\s*$/)?.[1])
  .find(Boolean)
  ?.replace(/^(?:"(.*)"|'(.*)')$/, (_, doubleQuoted, singleQuoted) => doubleQuoted ?? singleQuoted);

const buildContext = await context({
  entryPoints: ["src/main.ts"],
  bundle: true,
  format: "esm",
  outfile: "dist/bundle.js",
  target: "es2022",
  sourcemap: true,
  alias: {
    "@noble/hashes": "./node_modules/@noble/hashes",
    "@noble/curves": "./node_modules/@noble/curves",
  },
  define: {
    __MONAD_TESTNET_RPC__: JSON.stringify(configuredRpc ?? ""),
  },
});

if (process.argv.includes("--watch")) {
  await buildContext.watch();
} else {
  await buildContext.rebuild();
  await buildContext.dispose();
}
// ── stamp the stylesheet with its own hash ───────────────────────────────────────────────────
//
// A returning visitor gets the cached stylesheet, which during this project meant sliders
// rendering in the browser's default blue long after they had been restyled. The failure is
// invisible to whoever changed the CSS, because their own reload happened to miss the cache, and
// it lands on exactly the people a demo is being shown to. Hashing the file into the link means a
// changed stylesheet is a changed URL, and the cache stops being a question anybody has to think
// about.
const cssPath = new URL("./assets/croom.css", import.meta.url);
const cssHash = createHash("sha256").update(readFileSync(cssPath)).digest("hex").slice(0, 10);

const pages = [
  "index.html",
  "app/index.html",
  ...readdirSync(new URL("./blog", import.meta.url))
    .filter((f) => f.endsWith(".html"))
    .map((f) => `blog/${f}`),
];

let stamped = 0;
for (const page of pages) {
  const url = new URL(`./${page}`, import.meta.url);
  const html = readFileSync(url, "utf8");
  const next = html.replace(
    /(href="\.{1,2}\/assets\/croom\.css)(\?v=[0-9a-f]+)?"/g,
    `$1?v=${cssHash}"`,
  );
  if (next !== html) {
    writeFileSync(url, next);
    stamped += 1;
  }
}
console.log(`croom.css ${cssHash} — ${stamped} page(s) restamped`);
