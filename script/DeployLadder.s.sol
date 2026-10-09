// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Ladder} from "../src/Ladder.sol";
import {Registry} from "../src/Registry.sol";
import {Script, console} from "forge-std/Script.sol";

/// @notice Deploys `Ladder` against the live `Registry`.
///
/// ```bash
/// make deploy-ladder REGISTRY=0x...
/// ```
contract DeployLadder is Script {
    address internal constant EXPECTED_DEPLOYER = 0xc50f1FbD1c36a2305B257376eb2264C3bB6179e8;

    /// @dev Spec v1.1 Appendix C's production challenge window: 30 minutes at 3-second rounds.
    /// We can use the production value rather than a shortened demo one because the window is
    /// measured in **rounds above the proven floor**, and the floor only moves when somebody
    /// proves a round — so the window's passage is under the operator's control, not the clock's.
    uint64 internal constant CHALLENGE_ROUNDS = 600;

    uint256 internal constant BOND = 0.05 ether;

    function run() external {
        address expected = vm.envOr("EXPECTED_DEPLOYER", EXPECTED_DEPLOYER);
        if (msg.sender != expected) {
            console.log("expected deployer:", expected);
            console.log("actual deployer:  ", msg.sender);
            revert("wrong deployer: pass --sender as well as --account");
        }

        Registry registry = Registry(vm.envAddress("REGISTRY"));

        vm.startBroadcast();
        Ladder ladder = new Ladder(registry, BOND, CHALLENGE_ROUNDS);
        vm.stopBroadcast();

        console.log("Ladder deployed: ", address(ladder));
        console.log("registry:        ", address(registry));
        console.log("bond (wei):      ", BOND);
        console.log("challenge rounds:", CHALLENGE_ROUNDS);
    }
}
