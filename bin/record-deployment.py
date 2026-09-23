#!/usr/bin/env python3
"""Turn a forge broadcast artifact into deployment records.

The Solidity script cannot write these itself: inside `forge script` the block number is the
simulation's, not the broadcast's, and the transaction hash does not exist yet. Recording from
the broadcast artifact instead means every field is what actually happened on chain.

    bin/record-deployment.py broadcast/DeployProbe.s.sol/10143/run-latest.json
"""
import json
import pathlib
import subprocess
import sys


def main(artifact_path: str) -> int:
    art = json.loads(pathlib.Path(artifact_path).read_text())
    receipts = {r["transactionHash"].lower(): r for r in art["receipts"]}
    chain = art["chain"]
    commit = art.get("commit", "unknown")

    out_dir = pathlib.Path("deployments") / str(chain)
    out_dir.mkdir(parents=True, exist_ok=True)

    solc = subprocess.run(
        ["sh", "-c", "grep -E '^(solc_version|evm_version|optimizer_runs)' foundry.toml | tr -d ' \"'"],
        capture_output=True, text=True,
    ).stdout.split()

    written = []
    for tx in art["transactions"]:
        if tx.get("transactionType") != "CREATE":
            continue
        receipt = receipts.get(tx["hash"].lower())
        if receipt is None or int(receipt["status"], 16) != 1:
            print(f"skipping {tx.get('contractName')}: no successful receipt", file=sys.stderr)
            continue

        gas_used = int(receipt["gasUsed"], 16)
        price = int(receipt["effectiveGasPrice"], 16)
        record = {
            "contract": tx["contractName"],
            "address": subprocess.run(
                ["cast", "to-check-sum-address", tx["contractAddress"]],
                capture_output=True, text=True,
            ).stdout.strip(),
            "chainId": chain,
            "txHash": tx["hash"],
            "block": int(receipt["blockNumber"], 16),
            "deployer": subprocess.run(
                ["cast", "to-check-sum-address", receipt["from"]],
                capture_output=True, text=True,
            ).stdout.strip(),
            "gasUsed": gas_used,
            "effectiveGasPriceWei": price,
            "paidWei": gas_used * price,
            "commit": commit,
            "compiler": " ".join(solc),
        }
        path = out_dir / f"{record['contract']}.json"
        path.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
        written.append(str(path))
        print(f"{record['contract']:20s} {record['address']}  block {record['block']}")

    if not written:
        print("no CREATE transactions found", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
