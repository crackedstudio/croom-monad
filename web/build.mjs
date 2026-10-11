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
// ── stamp the assets with their own hashes ───────────────────────────────────────────────────
//
// A returning visitor gets the cached copy. During this project that meant sliders rendering in
// the browser's default blue long after they had been restyled, and then — worse, because it wastes
// far more time — an afternoon of debugging a tour against a stale bundle, where every fix appeared
// to do nothing because the browser was still running the previous build. The failure is invisible
// to whoever made the change, and it lands on exactly the people a demo is being shown to.
//
// Hashing each asset into its own URL means a changed file is a changed URL, and the cache stops
// being something anybody has to think about. The bundle is hashed after esbuild has written it.
const hashOf = (url) => createHash("sha256").update(readFileSync(url)).digest("hex").slice(0, 10);

const cssHash = hashOf(new URL("./assets/croom.css", import.meta.url));
const jsHash = hashOf(new URL("./dist/bundle.js", import.meta.url));

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
  const next = html
    .replace(/(href="\.{1,2}\/assets\/croom\.css)(\?v=[0-9a-f]+)?"/g, `$1?v=${cssHash}"`)
    .replace(/(src="\.{1,2}\/dist\/bundle\.js)(\?v=[0-9a-f]+)?"/g, `$1?v=${jsHash}"`);
  if (next !== html) {
    writeFileSync(url, next);
    stamped += 1;
  }
}
console.log(`css ${cssHash} · js ${jsHash} — ${stamped} page(s) restamped`);
