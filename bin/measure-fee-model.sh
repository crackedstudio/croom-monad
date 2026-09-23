#!/usr/bin/env bash
# Settles the single biggest behavioural difference in PLAN.md §4: does Monad charge the sender
# `gas_bid × gas_limit`, or `gas_bid × gas_used`?
#
# The deployment could not answer it. forge set the gas limit equal to the gas actually used, so
# both models predicted the same debit to the wei. This sends one transaction with a deliberately
# padded limit, where the two models differ by hundreds of thousands of gas, and reads the answer
# off the balance.
#
# The same transaction doubles as the real-transaction re-measurement of 0x08 that bench/
# precompiles.md still owes, since eth_call is the same EVM but not the same accounting path.
#
#   bin/measure-fee-model.sh <GasProbe address> [gas limit]
set -euo pipefail

PROBE="${1:?usage: measure-fee-model.sh <GasProbe address> [gas limit]}"
LIMIT="${2:-2000000}"
RPC="${RPC_URL:-https://testnet-rpc.monad.xyz}"
ACCOUNT="${DEPLOYER_ACCOUNT:-croom-deployer}"
SENDER="${DEPLOYER_ADDRESS:-0xc50f1FbD1c36a2305B257376eb2264C3bB6179e8}"

# Two balanced BN254 pairs: e(G1,G2)·e(-G1,G2) = 1. Exactly the shape of a drand verification.
P=21888242871839275222246405745257275088696311157297823662689037894645226208583
G2X1=11559732032986387107991004021392285783925812861821192530917403151452391805634
G2X0=10857046999023057135944570762232829481370756359578518086990519993285655852781
G2Y1=4082367875863433681332203403145435568316851327593401208105741076214120093531
G2Y0=8495653923123431417604973247489272438418190587263600148770280649306958101930
INPUT=$(cast abi-encode "f(uint256[12])" \
  "[1,2,$G2X1,$G2X0,$G2Y1,$G2Y0,1,$((P-2)),$G2X1,$G2X0,$G2Y1,$G2Y0]")

echo "probe:     $PROBE"
echo "sender:    $SENDER"
echo "gas limit: $LIMIT  (padded well above what the call needs)"
echo

BEFORE=$(cast balance "$SENDER" --rpc-url "$RPC")
TX=$(cast send "$PROBE" "checkPairing(bytes)" "$INPUT" \
      --gas-limit "$LIMIT" --rpc-url "$RPC" \
      --account "$ACCOUNT" --from "$SENDER" --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["transactionHash"])')
AFTER=$(cast balance "$SENDER" --rpc-url "$RPC")

USED=$(cast receipt "$TX" --rpc-url "$RPC" gasUsed)
PRICE=$(cast receipt "$TX" --rpc-url "$RPC" effectiveGasPrice)

python3 - "$BEFORE" "$AFTER" "$USED" "$PRICE" "$LIMIT" "$TX" <<'PY'
import sys
before, after, used, price, limit, tx = (int(x, 0) if i < 5 else x for i, x in enumerate(sys.argv[1:]))
spent = before - after
by_used, by_limit = used * price, limit * price
print(f"tx:            {tx}")
print(f"gas used:      {used:,}")
print(f"gas limit:     {limit:,}")
print(f"price:         {price/1e9:.0f} gwei")
print()
print(f"actually spent {spent/1e18:.18f} MON")
print(f"gas_used  model{by_used/1e18:>22.18f} MON   (off by {abs(spent-by_used)/1e18:.18f})")
print(f"gas_limit model{by_limit/1e18:>22.18f} MON   (off by {abs(spent-by_limit)/1e18:.18f})")
print()
print(f"VERDICT: charged on {'GAS_LIMIT' if abs(spent-by_limit) < abs(spent-by_used) else 'GAS_USED'}")
print(f"\n0x08 end-to-end, real transaction: {used:,} gas")
PY
