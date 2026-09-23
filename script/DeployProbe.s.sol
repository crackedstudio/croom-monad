// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {GasProbe} from "../src/probe/GasProbe.sol";
import {StoragePageProbe} from "../src/probe/StoragePageProbe.sol";
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
    /// @dev The `croom-deployer` keystore, confirmed by `make whoami-deployer` and holding the
    /// faucet's 5 MON. Deploying from anything else is a mistake worth catching before it costs a
    /// transaction — there are four keystores on this machine and a keystore file does not carry
    /// its address in the clear, so the only way to know is to ask it.
    ///
    /// This constant was briefly wrong: it held the `to` address of the faucet transaction, which
    /// is the faucet *contract* rather than the recipient. The assertion is what surfaced that.
    address internal constant EXPECTED_DEPLOYER = 0xc50f1FbD1c36a2305B257376eb2264C3bB6179e8;

    function run() external {
        address deployer = msg.sender;
        address expected = vm.envOr("EXPECTED_DEPLOYER", EXPECTED_DEPLOYER);

        if (deployer != expected) {
            console.log("expected deployer:", expected);
            console.log("actual deployer:  ", deployer);
            // 0x1804c8AB... is Foundry's default sender. Seeing it here means --sender was
            // omitted: --account alone is consulted only at broadcast, so the simulation ran
            // as nobody in particular and this check fired before any password prompt.
            if (deployer == 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38) {
                console.log("that is Foundry's default sender - add --sender");
            }
            revert("wrong deployer: pass --sender as well as --account, or set EXPECTED_DEPLOYER");
        }
        require(deployer.balance > 0, "deployer has no balance");

        vm.startBroadcast();
        GasProbe probe = new GasProbe();
        StoragePageProbe pages = new StoragePageProbe();
        vm.stopBroadcast();

        console.log("GasProbe deployed:        ", address(probe));
        console.log("StoragePageProbe deployed:", address(pages));

        // A simulation must not leave behind a file asserting that something was deployed.
        // deployments/ is the source the README's address table is generated from, and a
        // plausible-looking wrong address is worse there than no address at all.
        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            _record("GasProbe", address(probe), deployer);
            _record("StoragePageProbe", address(pages), deployer);
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
