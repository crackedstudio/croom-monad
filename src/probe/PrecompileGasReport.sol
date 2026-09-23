// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Bn254} from "./Bn254.sol";

/// @title PrecompileGasReport
/// @notice Step 1.5. Same constructor-return trick as `PairingGasReport`: run it through
/// `eth_call --create` and the numbers that come back are the node's own gas schedule.
///
/// Measures every primitive the protocol will actually use, so the gas table in the submission is
/// built from measurements rather than from Ethereum's published costs.
contract PrecompileGasReport {
    constructor() {
        uint256[7] memory g;

        g[0] = _probe(0x01, _ecRecoverInput()); // ecRecover
        g[1] = _probe(0x02, abi.encodePacked(bytes32(0))); // sha256, one word
        g[2] = _probe(0x04, abi.encodePacked(bytes32(0))); // identity, one word
        g[3] = _probe(0x06, _ecAddInput()); // ecAdd  — G1 + G1
        g[4] = _probe(0x07, _ecMulInput()); // ecMul  — G1 * 2
        g[5] = _probe(0x08, Bn254.balancedInput(2)); // ecPairing, 2 points
        g[6] = _keccakGas(); // KECCAK256 over 32 bytes, as an opcode

        bytes memory out = abi.encode(g);
        assembly {
            return(add(out, 0x20), mload(out))
        }
    }

    function _probe(
        uint256 addr,
        bytes memory input
    ) private view returns (uint256 gasUsed) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            let before := gas()
            let ok := staticcall(gas(), addr, add(input, 0x20), mload(input), ptr, 0x20)
            gasUsed := sub(before, gas())
            // A precompile that reverted on malformed input would report a meaningless figure.
            if iszero(ok) { gasUsed := 0 }
        }
    }

    function _keccakGas() private view returns (uint256 gasUsed) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            // Must not be a compile-time constant: the optimizer folds keccak256 of known
            // memory into a literal, which measures the optimizer rather than the opcode.
            mstore(ptr, timestamp())
            let before := gas()
            let h := keccak256(ptr, 0x20)
            gasUsed := sub(before, gas())
            // The hash must stay observable or the optimizer deletes the opcode we are timing.
            if iszero(h) { gasUsed := 0 }
        }
    }

    /// @dev Signature values are arbitrary: `ecRecover` charges before it decides whether the
    /// signature recovers to anything, which is exactly the behaviour worth measuring on a chain
    /// that bills the gas limit.
    function _ecRecoverInput() private pure returns (bytes memory) {
        return abi.encode(bytes32(uint256(1)), uint256(27), uint256(2), uint256(3));
    }

    function _ecAddInput() private pure returns (bytes memory) {
        return abi.encode(Bn254.G1_X, Bn254.G1_Y, Bn254.G1_X, Bn254.G1_Y);
    }

    function _ecMulInput() private pure returns (bytes memory) {
        return abi.encode(Bn254.G1_X, Bn254.G1_Y, uint256(2));
    }
}
