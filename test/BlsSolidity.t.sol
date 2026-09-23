// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BLS} from "bls-solidity/libraries/BLS.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Turns the conclusions of `docs/audits/bls-solidity.md` into tests, so they stay true
/// through a dependency bump instead of living only in prose. Runs offline against the pinned
/// fixtures in `test/fixtures/drand/`.
contract BlsSolidityTest is Test {
    /// @dev drand evmnet's tag, from `EvmnetRegistry`.
    string internal constant DST = "BLS_SIG_BN254G1_XMD:KECCAK-256_SVDW_RO_NUL_";

    /// @dev The tag `BN254SignatureScheme` would build on Monad testnet: chain-id derived, and
    /// belonging to Randamu's threshold network rather than to drand.
    string internal constant WRONG_DST = "app-BN254G1_XMD:KECCAK-256_SVDW_RO_0x...2797_";

    function _publicKey() internal pure returns (BLS.PointG2 memory) {
        return BLS.PointG2(
            [
                0x0557ec32c2ad488e4d4f6008f89a346f18492092ccc0d594610de2732c8b808f,
                0x07e1d1d335df83fa98462005690372c643340060d205306a9aa8106b6bd0b382
            ],
            [
                0x297d3a4f9749b33eb2d904c9d9ebf17224150ddd7abd7567a9bec6c74480ee0b,
                0x0095685ae3a85ba243747b1b2f426049010f6b73a0cf1d389351d5aaaa1047f6
            ]
        );
    }

    function _sig(
        string memory round
    ) internal view returns (bytes memory) {
        string memory json = vm.readFile(string.concat("test/fixtures/drand/rounds/", round, ".json"));
        return vm.parseJsonBytes(json, ".signature");
    }

    function _verify(
        uint64 round,
        bytes memory signature,
        string memory dst
    ) internal view returns (bool) {
        BLS.PointG1 memory message =
            BLS.hashToPoint(bytes(dst), abi.encodePacked(keccak256(abi.encodePacked(round))));
        (bool pairingOk, bool callOk) = BLS.verifySingle(BLS.g1Unmarshal(signature), _publicKey(), message);
        return pairingOk && callOk;
    }

    /// @dev The hardcoded public key must be the one the beacon actually publishes. Compared word
    /// for word against the committed `info.json` rather than eyeballed.
    function test_PublicKeyMatchesTheBeaconsOwnInfo() public view {
        bytes memory published =
            vm.parseJsonBytes(vm.readFile("test/fixtures/drand/info.json"), ".public_key");
        BLS.PointG2 memory pk = _publicKey();
        // The API serves the four words as x[1], x[0], y[1], y[0].
        bytes memory reconstructed = abi.encodePacked(pk.x[1], pk.x[0], pk.y[1], pk.y[0]);
        assertEq(reconstructed, published, "hardcoded public key does not match the beacon");
    }

    function test_RealRoundsVerify() public view {
        assertTrue(_verify(1, _sig("1"), DST), "round 1");
        assertTrue(_verify(1000, _sig("1000"), DST), "round 1000");
        assertTrue(_verify(20_880_831, _sig("20880831"), DST), "round 20880831");
    }

    /// @dev The trap from the audit. With the wrong domain separation tag a genuine signature and
    /// a genuine public key still fail, and the failure is indistinguishable from a forged
    /// signature. This test exists so that the distinction is never rediscovered by debugging.
    function test_WrongDstRejectsAGenuineSignature() public view {
        assertFalse(_verify(20_880_831, _sig("20880831"), WRONG_DST), "wrong DST must not verify");
    }

    /// @dev A signature is bound to its round. Replaying round 1000's signature as round 1 must
    /// fail, or the proven floor could be advanced arbitrarily from one valid signature.
    function test_SignatureIsBoundToItsRound() public view {
        assertFalse(_verify(1, _sig("1000"), DST), "round 1000 signature verified as round 1");
        assertFalse(_verify(1000, _sig("1"), DST), "round 1 signature verified as round 1000");
    }

    /// @dev Watch this one's gas figure: flipping a bit puts the point off the curve, 0x08
    /// reverts, and the precompile consumes every unit forwarded to it — the test reports over a
    /// billion gas. On Monad, where the limit is the price (bench/fee-model.md), that is a whole
    /// transaction's budget spent on rejecting one bad signature.
    function test_TamperedSignatureFails() public view {
        bytes memory sig = _sig("20880831");
        sig[63] = bytes1(uint8(sig[63]) ^ 0x01); // flip one bit of y
        assertFalse(_verify(20_880_831, sig, DST), "tampered signature verified");
    }

    /// @dev BN254 G1 has cofactor 1, so range plus on-curve is a complete validity check. This is
    /// what `Entropy` will call before touching 0x08, since a malformed input makes the precompile
    /// burn the entire gas limit (bench/precompiles.md).
    function test_PointValidationAcceptsRealSignaturesAndRejectsJunk() public pure {
        assertTrue(BLS.isValidPointG1(BLS.PointG1(1, 2)), "generator rejected");
        assertFalse(BLS.isValidPointG1(BLS.PointG1(1, 3)), "off-curve point accepted");
        uint256 n =
            21_888_242_871_839_275_222_246_405_745_257_275_088_696_311_157_297_823_662_689_037_894_645_226_208_583;
        assertFalse(BLS.isValidPointG1(BLS.PointG1(n, 2)), "out-of-range x accepted");
    }
}
