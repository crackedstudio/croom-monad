#!/usr/bin/env bash
# Measures the cost of verifying real drand evmnet rounds on Monad, across a sample of rounds.
#
# Hash-to-point runs SVDW, whose Legendre/square-root branches differ from round to round, so the
# cost is round-dependent. On a chain that bills the gas limit, a limit derived from one round can
# be too low for another — and a limit that is too low means the transaction reverts AND is charged
# in full. The number that matters operationally is therefore the maximum, not the mean.
#
#   bin/sample-verify-gas.sh [count] [stride] > bench/verify-gas.csv
set -uo pipefail

COUNT="${1:-24}"
STRIDE="${2:-977}"      # coprime-ish with anything periodic, to avoid sampling a pattern
RPC="${RPC_URL:-https://testnet-rpc.monad.xyz}"
CHAIN=04f1e9062b8a81f848fded9c12306733282b2727ecced50032187751166ec8c3
API="https://api.drand.sh/v2/chains/$CHAIN"

fetch_sig() {                       # $1 = round; retries, because the API rate-limits bursts
  local round="$1" attempt sig
  for attempt in 1 2 3 4; do
    sig=$(curl -sS --max-time 20 "$API/rounds/$round" 2>/dev/null \
          | python3 -c 'import sys,json
try: print(json.load(sys.stdin)["signature"])
except Exception: pass' 2>/dev/null)
    if [ -n "$sig" ]; then printf '%s' "$sig"; return 0; fi
    sleep $((attempt * 2))
  done
  return 1
}

CODE=$(forge inspect src/probe/BeaconVerifyReport.sol:BeaconVerifyReport bytecode)
LATEST=$(fetch_sig latest >/dev/null 2>&1; curl -sS --max-time 20 "$API/rounds/latest" \
         | python3 -c 'import sys,json;print(json.load(sys.stdin)["round"])')

echo "round,verified,gas_hash_to_point,gas_pairing,gas_total"
for i in $(seq 0 $((COUNT - 1))); do
  ROUND=$((LATEST - i * STRIDE))
  SIG=$(fetch_sig "$ROUND") || { echo "# round $ROUND: fetch failed after retries" >&2; continue; }
  ARGS=$(cast abi-encode "c(uint64,bytes)" "$ROUND" "0x$SIG")
  OUT=$(cast call --rpc-url "$RPC" --create "${CODE}${ARGS:2}" 2>/dev/null) || {
    echo "# round $ROUND: eth_call failed" >&2; continue; }
  cast decode-abi 'f()(bool,uint256,uint256,uint256)' "$OUT" \
    | tr -d '[]' | awk "{print \$1}" | paste -sd, - | sed "s/^/$ROUND,/"
  sleep 0.3
done
