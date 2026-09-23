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
#
# NEG_G1_Y is the field modulus minus 2, written out in full. It must NOT be computed in the
# shell: bash arithmetic is 64-bit and silently truncates a 77-digit literal to a negative
# number. That mistake cost a transaction and 0.204 MON — the mangled coordinate was off-curve,
# 0x08 reverted, and a reverting precompile consumes every gas unit forwarded to it, so the
# receipt showed gas_used == gas_limit and the experiment proved nothing.
NEG_G1_Y=21888242871839275222246405745257275088696311157297823662689037894645226208581
G2X1=11559732032986387107991004021392285783925812861821192530917403151452391805634
G2X0=10857046999023057135944570762232829481370756359578518086990519993285655852781
G2Y1=4082367875863433681332203403145435568316851327593401208105741076214120093531
G2Y0=8495653923123431417604973247489272438418190587263600148770280649306958101930
INPUT=$(cast abi-encode "f(uint256[12])" \
  "[1,2,$G2X1,$G2X0,$G2Y1,$G2Y0,1,$NEG_G1_Y,$G2X1,$G2X0,$G2Y1,$G2Y0]")

echo "probe:     $PROBE"
echo "sender:    $SENDER"
echo "gas limit: $LIMIT  (padded well above what the call needs)"
echo

# Pre-flight, free: prove the input is well formed before paying to send it. An off-curve point
# makes 0x08 revert and burn the whole limit, which looks exactly like a chain that bills the
# limit — an indistinguishable false positive for the very thing being measured.
PREFLIGHT=$(cast call "$PROBE" "checkPairing(bytes)(bool)" "$INPUT" --rpc-url "$RPC")
if [ "$PREFLIGHT" != "true" ]; then
  echo "ABORT: pairing input is not valid (checkPairing returned $PREFLIGHT)." >&2
  echo "Sending it would burn the full gas limit and measure nothing." >&2
  exit 1
fi
INNER=$(cast call "$PROBE" "probePairing(uint256,bytes)(uint256,bool,bool)" 2 "$INPUT" --rpc-url "$RPC" | head -1)
echo "pre-flight: input valid, 0x08 inner gas by eth_call = $INNER"
echo

BEFORE=$(cast balance "$SENDER" --rpc-url "$RPC")
TX=$(cast send "$PROBE" "checkPairing(bytes)" "$INPUT" \
      --gas-limit "$LIMIT" --rpc-url "$RPC" \
      --account "$ACCOUNT" --from "$SENDER" --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["transactionHash"])')
AFTER=$(cast balance "$SENDER" --rpc-url "$RPC")

# NOTE: on Monad `receipt.gasUsed` reports the BILLED gas, which equals the limit. Comparing the
# balance delta against it is circular and always "proves" the gas_used model. The honest
# reference for what the call actually executes is an independent estimate.
USED=$(cast receipt "$TX" --rpc-url "$RPC" gasUsed)
EXECUTED=$(cast estimate "$PROBE" "checkPairing(bytes)" "$INPUT" --rpc-url "$RPC" --from "$SENDER")
PRICE=$(cast receipt "$TX" --rpc-url "$RPC" effectiveGasPrice)

python3 - "$BEFORE" "$AFTER" "$EXECUTED" "$PRICE" "$LIMIT" "$TX" "$USED" <<'PY'
import sys
before, after, executed, price, limit, tx, billed = (
    int(x, 0) if i != 5 else x for i, x in enumerate(sys.argv[1:]))
spent = before - after
by_used, by_limit = executed * price, limit * price
print(f"receipt gasUsed: {int(billed,0):,}  (the BILLED figure on Monad, not the executed one)")
print(f"eth_estimateGas: {executed:,}  (what the call actually needs)")
print(f"tx:            {tx}")
print(f"gas used:      {used:,}")
print(f"gas limit:     {limit:,}")
print(f"price:         {price/1e9:.0f} gwei")
print()
print(f"actually spent {spent/1e18:.18f} MON")
print(f"gas_used  model{by_used/1e18:>22.18f} MON   (off by {abs(spent-by_used)/1e18:.18f})")
print(f"gas_limit model{by_limit/1e18:>22.18f} MON   (off by {abs(spent-by_limit)/1e18:.18f})")
print()
if executed >= limit:
    print("VERDICT: INCONCLUSIVE - the call needs at least the limit, so the models coincide.")
    print("         Re-run with a larger limit.")
else:
    print(f"VERDICT: charged on {'GAS_LIMIT' if abs(spent-by_limit) < abs(spent-by_used) else 'GAS_USED'}")
    print(f"         padding cost {(by_limit-by_used)/1e18:.6f} MON on this transaction alone")
PY
