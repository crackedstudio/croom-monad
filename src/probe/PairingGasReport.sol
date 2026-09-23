// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Bn254} from "./Bn254.sol";

/// @title PairingGasReport
/// @notice Measures `0x08` on a live network **without deploying anything and without spending
/// anything**, by doing the work in a constructor and returning the measurements where the runtime
/// code would normally go.
///
/// ```
/// cast call --create $(forge inspect PairingGasReport bytecode) --rpc-url monad_testnet
/// ```
///
/// `eth_call` meters with the node's real gas schedule, so the numbers that come back are Monad's
/// own prices, not Ethereum's. This turns step 1.4 — the day-one gate, and the highest-risk item in
/// the whole plan — into a read-only query answerable before a faucet claim has cleared.
///
/// Step 1.4 still re-measures through a real transaction once a deployer is funded: `eth_call` is
/// the same EVM but it is not the same accounting path, and a gate that decides the architecture
/// deserves both numbers.
contract PairingGasReport {
    constructor() {
        uint256[4] memory innerGas;
        bool[4] memory results;

        for (uint256 k = 1; k <= 4; k++) {
            bytes memory input = Bn254.balancedInput(k);
            uint256 gasUsed;
            bool ok;
            bool isOne;

            assembly ("memory-safe") {
                let ptr := mload(0x40)
                let len := mload(input)
                let before := gas()
                ok := staticcall(gas(), 0x08, add(input, 0x20), len, ptr, 0x20)
                gasUsed := sub(before, gas())
                isOne := and(ok, eq(mload(ptr), 1))
            }

            innerGas[k - 1] = gasUsed;
            results[k - 1] = isOne;
        }

        bytes memory out = abi.encode(innerGas, results);
        assembly {
            return(add(out, 0x20), mload(out))
        }
    }
}
