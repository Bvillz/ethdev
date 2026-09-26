// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRandomnessProvider, IRandomnessConsumer} from "./IRandomness.sol";

/// @title TESTNET ONLY randomness
/// @notice The owner (your keeper bot) supplies the random number. That means the owner could
///         choose the winner, so never use this with real money. Use ChainlinkVRFProvider on mainnet.
contract ManualRandomnessProvider is IRandomnessProvider, Ownable {
    address public consumer;
    uint256 public nextRequestId = 1;
    mapping(uint256 => bool) public pending;

    event Requested(uint256 indexed requestId);

    error ConsumerAlreadySet();
    error OnlyConsumer();
    error UnknownRequest();

    constructor() Ownable(msg.sender) {}

    function setConsumer(address consumer_) external onlyOwner {
        if (consumer != address(0)) revert ConsumerAlreadySet();
        consumer = consumer_;
    }

    function requestFee() external pure returns (uint256) {
        return 0;
    }

    function requestRandomness() external payable returns (uint256 requestId) {
        if (msg.sender != consumer) revert OnlyConsumer();
        requestId = nextRequestId++;
        pending[requestId] = true;
        emit Requested(requestId);
    }

    function fulfill(uint256 requestId, uint256 randomWord) external onlyOwner {
        if (!pending[requestId]) revert UnknownRequest();
        delete pending[requestId];
        IRandomnessConsumer(consumer).fulfillRandomness(requestId, randomWord);
    }
}
