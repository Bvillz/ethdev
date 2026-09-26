// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice A source of random numbers the flywheel asks for once per spin.
interface IRandomnessProvider {
    /// @notice ETH the caller must send with requestRandomness (0 if paid another way).
    function requestFee() external view returns (uint256);

    /// @notice Ask for a random number. The provider later calls fulfillRandomness on its consumer.
    function requestRandomness() external payable returns (uint256 requestId);
}

/// @notice Implemented by the flywheel to receive random numbers.
interface IRandomnessConsumer {
    function fulfillRandomness(uint256 requestId, uint256 randomWord) external;
}
