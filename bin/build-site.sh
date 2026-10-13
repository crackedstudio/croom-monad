#!/usr/bin/env bash
# Assembles the deployable site into site/ — and nothing else.
#
# Two things must never reach a public host, and both live in web/:
#   web/.env             the keyed RPC endpoint
#   web/node_modules     ~100MB of nothing anybody needs
#
# `wrangler pages deploy web` would upload both. So the site is assembled by allowlist rather than
# excluded by denylist: only the files named here ship, and a new secret dropped into web/ later
# cannot be published by accident.
#
# The bundle is built with MONAD_TESTNET_RPC empty, because whatever endpoint is configured gets
# compiled into the JavaScript and is readable by anyone who views source. The app falls back to
# three public endpoints.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=site
rm -rf "$OUT"
mkdir -p "$OUT"

MONAD_TESTNET_RPC= make web >/dev/null
echo "built with public endpoints only"

cp web/index.html "$OUT/"
cp -R web/assets "$OUT/assets"
cp -R web/app "$OUT/app"
cp -R web/blog "$OUT/blog"
mkdir -p "$OUT/dist"
cp web/dist/bundle.js "$OUT/dist/bundle.js"

# A sourcemap is 2MB of our TypeScript served to everyone. Useful locally, not on a public host.
rm -f "$OUT/dist/bundle.js.map"

# Cache rules and headers for Pages. Written here rather than kept in the repo root so that the
# output directory is entirely a build product and can be deleted without losing anything.
cp deploy/_headers "$OUT/_headers"

# Without a 404.html, Pages answers any invented path with index.html and a 200 — so probing
# /.env returned "success" and a page. Nothing was leaking, but a site arguing for verifiability
# should not report success for something that does not exist.
cp deploy/404.html "$OUT/404.html"

# Two checks, both precise. A generic "32 hex characters" rule was tried first and matched every
# zero-padded EVM word in the bundle, which is the kind of guard people learn to ignore.
if grep -rqE 'infura|alchemy|quicknode|chainstack|blastapi|nodereal' "$OUT"; then
  echo "REFUSING TO SHIP: a keyed RPC provider appears in the output." >&2
  grep -rlE 'infura|alchemy|quicknode|chainstack|blastapi|nodereal' "$OUT" >&2
  exit 1
fi

# Whatever is actually configured locally, verbatim. This stays correct when the secret changes.
if [ -f web/.env ]; then
  while IFS= read -r secret; do
    [ -z "$secret" ] && continue
    if grep -rqF -- "$secret" "$OUT"; then
      echo "REFUSING TO SHIP: a value from web/.env reached the output." >&2
      exit 1
    fi
  done < <(sed -n 's/^[^#][^=]*=[[:space:]]*//p' web/.env | tr -d '"'"'"'"' | sed '/^$/d')
fi
if find "$OUT" -name ".env" -o -name "node_modules" -type d | grep -q .; then
  echo "REFUSING TO SHIP: .env or node_modules reached the output." >&2
  exit 1
fi

echo
du -sh "$OUT"
find "$OUT" -type f | sed "s|^$OUT/||" | sort
