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
# Whatever endpoint is configured gets compiled into the JavaScript and is readable by anyone who
# views source, so the default is to compile none and lean on the three public endpoints.
#
# CROOM_PUBLIC_RPC is the deliberate exception: an endpoint meant to be public, restricted at the
# provider to this site's domain. It is checked before it ships, because an RPC that 404s is worse
# than no RPC at all, and it is the one keyed-looking string the secret guard below will tolerate.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=site
rm -rf "$OUT"
mkdir -p "$OUT"

PUBLIC_RPC="${CROOM_PUBLIC_RPC:-}"

if [ -n "$PUBLIC_RPC" ]; then
  echo "checking $(echo "$PUBLIC_RPC" | sed 's#\(://[^/]*\).*#\1/…#')"
  CHAIN=$(curl -s --max-time 15 -X POST "$PUBLIC_RPC" \
    -H 'content-type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
    | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
  if [ "$CHAIN" != "0x279f" ]; then
    echo "REFUSING TO SHIP: CROOM_PUBLIC_RPC did not answer as Monad testnet (got '${CHAIN:-no answer}', wanted 0x279f)." >&2
    exit 1
  fi
  echo "endpoint answers as Monad testnet (0x279f)"
fi

MONAD_TESTNET_RPC="$PUBLIC_RPC" make web >/dev/null
if [ -n "$PUBLIC_RPC" ]; then
  echo "built with the public endpoint compiled in"
else
  echo "built with public endpoints only"
fi

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
# Any keyed provider in the output is a mistake, except the one endpoint deliberately published
# through CROOM_PUBLIC_RPC. Stripping that exact string first means the check still catches
# everything else, including a second key pasted into the wrong place.
SCAN=$(mktemp -d)
cp -R "$OUT"/. "$SCAN"/
if [ -n "$PUBLIC_RPC" ]; then
  find "$SCAN" -type f -exec perl -pi -e "s/\Q$PUBLIC_RPC\E//g" {} + 2>/dev/null || true
fi
if grep -rqE 'infura|alchemy|quicknode|chainstack|blastapi|nodereal' "$SCAN"; then
  echo "REFUSING TO SHIP: a keyed RPC provider appears in the output." >&2
  grep -rlE 'infura|alchemy|quicknode|chainstack|blastapi|nodereal' "$SCAN" >&2
  rm -rf "$SCAN"; exit 1
fi
rm -rf "$SCAN"

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
