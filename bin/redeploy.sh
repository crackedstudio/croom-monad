#!/usr/bin/env bash
# Redeploys Ladder and Market after the `post` signature change, then regenerates the frontend's
# addresses. Run when connectivity returns.
#
#   bin/redeploy.sh [rpc-url]
#
# Ladder is immutable in Market (constructor argument), so replacing one replaces both. The
# Registry and Entropy are untouched: their interfaces did not change, and the 50 Rooms and the
# proven floor stay exactly where they are.
set -euo pipefail

RPC="${1:-https://testnet-rpc.monad.xyz}"
ACCOUNT="${DEPLOYER_ACCOUNT:-croom-deployer}"
SENDER="${DEPLOYER_ADDRESS:-0xc50f1FbD1c36a2305B257376eb2264C3bB6179e8}"
REGISTRY="${REGISTRY:-0xE583B914CF2d25fc278301b195aB090640b4eECA}"
PYTHON="${PYTHON:-/opt/homebrew/bin/python3}"

echo "rpc:      $RPC"
echo "sender:   $SENDER"
echo "registry: $REGISTRY"
echo

echo "== 1/3 deploying Ladder =="
REGISTRY="$REGISTRY" forge script script/DeployLadder.s.sol \
  --rpc-url "$RPC" --account "$ACCOUNT" --sender "$SENDER" --broadcast
"$PYTHON" bin/record-deployment.py broadcast/DeployLadder.s.sol/10143/run-latest.json

LADDER=$("$PYTHON" -c 'import json;print(json.load(open("deployments/10143/Ladder.json"))["address"])')
echo "Ladder: $LADDER"
echo

echo "== 2/3 deploying Market =="
LADDER="$LADDER" forge script script/DeployMarket.s.sol \
  --rpc-url "$RPC" --account "$ACCOUNT" --sender "$SENDER" --broadcast
"$PYTHON" bin/record-deployment.py broadcast/DeployMarket.s.sol/10143/run-latest.json

echo
echo "== 3/3 regenerating frontend addresses =="
"$PYTHON" bin/gen-addresses.py
(cd web && npm run build >/dev/null && echo "web bundle rebuilt")

echo
echo "Done. Next, the two-account fraud proof:"
echo "  make demo-post-lie  LADDER=$LADDER ACCOUNT=croom-liar        FROM=<liar>"
echo "  make demo-disprove  LADDER=$LADDER ACCOUNT=croom-challenger  FROM=<challenger>"
