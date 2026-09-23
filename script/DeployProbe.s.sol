// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {GasProbe} from "../src/probe/GasProbe.sol";
import {Script, console} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @notice Step 1.3 — the first real deployment, and the vehicle for re-measuring `0x08` through
/// an actual transaction rather than `eth_call`.
///
/// ```bash
/// forge script script/DeployProbe.s.sol --rpc-url monad_testnet \
///   --account croom-deployer --broadcast
/// ```
///
/// Writes `deployments/<chainid>/GasProbe.json`. The README's address table is generated from
/// those files, never hand-typed.
contract DeployProbe is Script {
    /// @dev The account funded at block 65004032. Deploying from anything else is a mistake worth
    /// catching before it costs a transaction, not after — there are four keystores on this
    /// machine and their addresses are not readable without a password.
    address internal constant EXPECTED_DEPLOYER = 0x631a6A936485FA0Cba53c37A671AAF505F16d08e;

    function run() external {
        address deployer = msg.sender;
        address expected = vm.envOr("EXPECTED_DEPLOYER", EXPECTED_DEPLOYER);

        if (deployer != expected) {
            console.log("expected deployer:", expected);
            console.log("actual deployer:  ", deployer);
            revert("wrong deployer: check --account, or set EXPECTED_DEPLOYER to override");
        }
        require(deployer.balance > 0, "deployer has no balance");

        vm.startBroadcast();
        GasProbe probe = new GasProbe();
        vm.stopBroadcast();

        console.log("GasProbe deployed:", address(probe));

        // A simulation must not leave behind a file asserting that something was deployed.
        // deployments/ is the source the README's address table is generated from, and a
        // plausible-looking wrong address is worse there than no address at all.
        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            _record("GasProbe", address(probe), deployer);
        } else {
            console.log("dry run: no deployment record written");
        }
    }

    function _record(
        string memory name,
        address addr,
        address deployer
    ) internal {
        string memory obj = "deployment";
        vm.serializeString(obj, "contract", name);
        vm.serializeAddress(obj, "address", addr);
        vm.serializeAddress(obj, "deployer", deployer);
        vm.serializeUint(obj, "chainId", block.chainid);
        vm.serializeUint(obj, "block", block.number);
        vm.serializeString(obj, "commit", vm.envOr("GIT_COMMIT", string("unknown")));
        string memory out = vm.serializeString(obj, "compiler", "solc 0.8.28, cancun, 1e6 runs");

        string memory dir = string.concat("deployments/", vm.toString(block.chainid));
        vm.createDir(dir, true);
        vm.writeJson(out, string.concat(dir, "/", name, ".json"));
    }
}
