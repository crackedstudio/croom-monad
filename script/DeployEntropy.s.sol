// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Entropy} from "../src/Entropy.sol";
import {Script, console} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @notice Step 2.5 — deploys `Entropy`. **Deployment only.**
///
/// Proving a round is deliberately *not* done here. `forge script` sizes gas limits by executing
/// in its own EVM, which uses Ethereum's schedule, and Monad's pairing costs 452,804 gas more than
/// Ethereum's. A `proveRound` in this script is sent with a limit about 2.4x too small, runs out
/// of gas, and — because Monad bills the limit — is charged in full. That happened once already;
/// see `bench/gas-estimation.md`.
///
/// Deployment estimates are fine: code deposit is priced the same on both chains.
///
/// ```bash
/// make deploy-entropy
/// make prove-round ENTROPY=0x...      # cast send with a measured limit
/// ```
contract DeployEntropy is Script {
    address internal constant EXPECTED_DEPLOYER = 0xc50f1FbD1c36a2305B257376eb2264C3bB6179e8;

    function run() external {
        address deployer = msg.sender;
        address expected = vm.envOr("EXPECTED_DEPLOYER", EXPECTED_DEPLOYER);
        if (deployer != expected) {
            console.log("expected deployer:", expected);
            console.log("actual deployer:  ", deployer);
            if (deployer == 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38) {
                console.log("that is Foundry's default sender - add --sender");
            }
            revert("wrong deployer: pass --sender as well as --account");
        }

        vm.startBroadcast();
        Entropy entropy = new Entropy();
        vm.stopBroadcast();

        console.log("Entropy deployed:", address(entropy));
        console.log("proven floor:    ", entropy.provenFloor());
        console.log("next: make prove-round ENTROPY=<address>");

        if (!vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            console.log("dry run: nothing broadcast, no deployment record");
        }
    }
}
