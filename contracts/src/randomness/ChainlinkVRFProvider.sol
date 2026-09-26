// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRandomnessProvider, IRandomnessConsumer} from "./IRandomness.sol";

/// @dev Minimal Chainlink VRF v2.5 types, matching VRFV2PlusClient in @chainlink/contracts.
library VRFV2PlusClient {
    bytes4 internal constant EXTRA_ARGS_V1_TAG = bytes4(keccak256("VRF ExtraArgsV1"));

    struct ExtraArgsV1 {
        bool nativePayment;
    }

    struct RandomWordsRequest {
        bytes32 keyHash;
        uint256 subId;
        uint16 requestConfirmations;
        uint32 callbackGasLimit;
        uint32 numWords;
        bytes extraArgs;
    }

    function argsToBytes(ExtraArgsV1 memory extraArgs) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(EXTRA_ARGS_V1_TAG, extraArgs);
    }
}

interface IVRFCoordinatorV2Plus {
    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata req) external returns (uint256 requestId);
}

/// @title Chainlink VRF v2.5 randomness for the Goofer Flywheel
/// @notice Uses a Chainlink VRF subscription, so spins cost nothing extra for the caller.
///         Add this contract as a consumer on the subscription at vrf.chain.link and keep it funded.
///         Nobody, including the deployer, can predict or change the random number.
contract ChainlinkVRFProvider is IRandomnessProvider, Ownable {
    IVRFCoordinatorV2Plus public immutable coordinator;
    bytes32 public immutable keyHash;
    uint256 public immutable subscriptionId;
    bool public immutable nativePayment;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant CALLBACK_GAS_LIMIT = 500_000;

    address public consumer;

    event ConsumerSet(address indexed consumer);

    error ConsumerAlreadySet();
    error OnlyConsumer();
    error OnlyCoordinator(address have, address want);
    error NoFeeNeeded();

    constructor(address coordinator_, bytes32 keyHash_, uint256 subscriptionId_, bool nativePayment_)
        Ownable(msg.sender)
    {
        coordinator = IVRFCoordinatorV2Plus(coordinator_);
        keyHash = keyHash_;
        subscriptionId = subscriptionId_;
        nativePayment = nativePayment_;
    }

    /// @notice Link the flywheel. Can only be done once.
    function setConsumer(address consumer_) external onlyOwner {
        if (consumer != address(0)) revert ConsumerAlreadySet();
        consumer = consumer_;
        emit ConsumerSet(consumer_);
    }

    function requestFee() external pure returns (uint256) {
        return 0;
    }

    function requestRandomness() external payable returns (uint256) {
        if (msg.sender != consumer) revert OnlyConsumer();
        if (msg.value != 0) revert NoFeeNeeded();
        return coordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: CALLBACK_GAS_LIMIT,
                numWords: 1,
                extraArgs: VRFV2PlusClient.argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: nativePayment}))
            })
        );
    }

    /// @notice Called by the Chainlink coordinator with the random number.
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        if (msg.sender != address(coordinator)) revert OnlyCoordinator(msg.sender, address(coordinator));
        IRandomnessConsumer(consumer).fulfillRandomness(requestId, randomWords[0]);
    }
}
