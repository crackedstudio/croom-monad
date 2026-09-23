// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice Step 2.1. Pins every assumption the verifier will make about the beacon, so that a
/// change upstream — or a mistyped constant in our own code — fails here with a diff rather than
/// as a signature that mysteriously will not verify.
contract DrandChainInfoTest is Test {
    /// @dev PLAN.md §3.1 asserts this hash. Confirmed against `https://api.drand.sh` on 2026-09-23.
    bytes32 internal constant EXPECTED_CHAIN_HASH =
        0x04f1e9062b8a81f848fded9c12306733282b2727ecced50032187751166ec8c3;

    string internal info;

    function setUp() public {
        info = vm.readFile("test/fixtures/drand/info.json");
    }

    function test_ChainHashMatchesThePlan() public view {
        bytes memory hash = vm.parseJsonBytes(info, ".chain_hash");
        // Assert the length before narrowing: a short hash would otherwise be zero-padded into a
        // bytes32 that could still compare equal to something, which is the exact failure this
        // test exists to catch.
        assertEq(hash.length, 32, "chain hash is not 32 bytes");
        // casting to 'bytes32' is safe because the length is asserted to be exactly 32 above.
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(bytes32(hash), EXPECTED_CHAIN_HASH, "evmnet chain hash is not what the plan states");
    }

    function test_SchemeIsUnchainedBn254OnG1() public view {
        // The whole sparse-floor design depends on "unchained": the signed message is the round
        // number alone, so any round verifies in isolation.
        assertEq(vm.parseJsonString(info, ".scheme"), "bls-bn254-unchained-on-g1");
        assertEq(vm.parseJsonString(info, ".beacon_id"), "evmnet");
    }

    function test_PeriodAndGenesisArePinned() public view {
        assertEq(vm.parseJsonUint(info, ".period"), 3, "beacon period changed");
        assertEq(vm.parseJsonUint(info, ".genesis_time"), 1_727_521_075, "genesis changed");
    }

    /// @dev 128 bytes is an uncompressed G2 point. If this ever becomes 64, the beacon switched to
    /// compressed encoding and the verifier needs a decompression step it does not currently have.
    function test_PublicKeyIsUncompressedG2() public view {
        assertEq(vm.parseJsonBytes(info, ".public_key").length, 128, "public key is not uncompressed G2");
    }

    /// @dev 64 bytes is an uncompressed G1 point: two 32-byte field elements, exactly the layout
    /// the `0x08` precompile wants. No square root, no 30,000-gas scalar multiplication.
    function test_SignaturesAreUncompressedG1() public view {
        string[6] memory rounds = ["1", "2", "1000", "1000000", "20880731", "20880831"];
        for (uint256 i = 0; i < rounds.length; i++) {
            string memory json = vm.readFile(string.concat("test/fixtures/drand/rounds/", rounds[i], ".json"));
            assertEq(vm.parseJsonBytes(json, ".signature").length, 64, "signature is not uncompressed G1");
            assertEq(vm.parseJsonUint(json, ".round"), vm.parseUint(rounds[i]), "round number mismatch");
        }
    }
}
