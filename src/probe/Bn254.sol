// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @notice BN254 (alt_bn128) constants and pairing-input construction.
/// @dev Every constant here is validated by `GasProbeTest.test_BalancedPairingIsOne` — if any were
/// mistranscribed the pairing would not evaluate to one. Nothing in this file is taken on trust.
library Bn254 {
    /// @dev Base field modulus.
    uint256 internal constant P =
        21_888_242_871_839_275_222_246_405_745_257_275_088_696_311_157_297_823_662_689_037_894_645_226_208_583;

    uint256 internal constant G1_X = 1;
    uint256 internal constant G1_Y = 2;

    // G2 generator, in the word order the `0x08` precompile expects: for each coordinate the
    // imaginary coefficient precedes the real one.
    uint256 internal constant G2_X1 =
        11_559_732_032_986_387_107_991_004_021_392_285_783_925_812_861_821_192_530_917_403_151_452_391_805_634;
    uint256 internal constant G2_X0 =
        10_857_046_999_023_057_135_944_570_762_232_829_481_370_756_359_578_518_086_990_519_993_285_655_852_781;
    uint256 internal constant G2_Y1 =
        4_082_367_875_863_433_681_332_203_403_145_435_568_316_851_327_593_401_208_105_741_076_214_120_093_531;
    uint256 internal constant G2_Y0 =
        8_495_653_923_123_431_417_604_973_247_489_272_438_418_190_587_263_600_148_770_280_649_306_958_101_930;

    /// @notice `pairs` pairs alternating G1 and -G1 against G2.
    /// @dev The product is one exactly when `pairs` is even. Gas is identical either way, which is
    /// the property we want to demonstrate on a chain that charges the gas limit.
    function balancedInput(
        uint256 pairs
    ) internal pure returns (bytes memory input) {
        for (uint256 i = 0; i < pairs; i++) {
            uint256 y = i % 2 == 0 ? G1_Y : P - G1_Y;
            input = bytes.concat(input, abi.encode(G1_X, y, G2_X1, G2_X0, G2_Y1, G2_Y0));
        }
    }

    /// @notice One pair whose G1 point does not satisfy y² = x³ + 3.
    function offCurveInput() internal pure returns (bytes memory) {
        return abi.encode(uint256(1), uint256(3), G2_X1, G2_X0, G2_Y1, G2_Y0);
    }
}
