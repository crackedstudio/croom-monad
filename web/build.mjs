import { readFileSync } from "node:fs";
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