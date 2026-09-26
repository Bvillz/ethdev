// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRandomnessProvider, IRandomnessConsumer} from "./randomness/IRandomness.sol";

interface IGooferToken {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function totalWeight() external view returns (uint256);
    function holderAt(uint256 point) external view returns (address);
    function lastBuyAt(address account) external view returns (uint64);
}

/// @title The Goofer Flywheel
/// @notice Holds the trade fees and, every `spinInterval`, pays the whole pot to one holder.
///         A holder's chance of winning equals their share of $GOOFER on the wheel.
///         Anyone can start a spin once it's due; the random number comes from `randomness`.
contract GooferFlywheel is IRandomnessConsumer, Ownable {
    /// @notice How many times to re-draw if the drawn wallet bought too recently.
    uint256 public constant MAX_DRAWS = 4;
    /// @notice After this long without an answer from the randomness provider, a spin can be retried.
    uint256 public constant REQUEST_TIMEOUT = 1 hours;

    IGooferToken public immutable token;
    uint256 public immutable spinInterval;
    /// @notice A winner must have held since at least this long before the spin was requested.
    uint256 public immutable minHoldTime;

    IRandomnessProvider public randomness;

    uint256 public round;
    uint256 public lastSpinAt;
    bool public spinPending;
    uint256 public pendingRequestId;
    uint256 public pendingRequestedAt;

    address public lastWinner;
    uint256 public lastPayout;
    uint256 public totalPaidOut;

    event SpinRequested(uint256 indexed round, uint256 indexed requestId, uint256 pot);
    event SpinWon(uint256 indexed round, address indexed winner, uint256 amount);
    event SpinRolledOver(uint256 indexed round, uint256 pot);
    event SpinCleared(uint256 indexed round, uint256 indexed requestId);
    event RandomnessSet(address indexed provider);

    error SpinNotDue(uint256 nextSpinAt);
    error SpinAlreadyPending();
    error NothingToSpin();
    error OnlyRandomness();
    error WrongRequest();
    error NotStuck();
    error WrongFee(uint256 required);

    constructor(address token_, address randomness_, uint256 spinInterval_, uint256 minHoldTime_) Ownable(msg.sender) {
        token = IGooferToken(token_);
        randomness = IRandomnessProvider(randomness_);
        spinInterval = spinInterval_;
        minHoldTime = minHoldTime_;
        emit RandomnessSet(randomness_);
    }

    // ---- Views for the website and keeper ------------------------------------------------------

    function pot() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function nextSpinAt() public view returns (uint256) {
        return lastSpinAt + spinInterval;
    }

    function canSpin() public view returns (bool) {
        return !spinPending && block.timestamp >= nextSpinAt() && pot() != 0 && token.totalWeight() != 0;
    }

    // ---- Spinning ------------------------------------------------------------------------------

    /// @notice Start a spin. Anyone can call this once it's due (the keeper bot does it every interval).
    function spin() external payable {
        if (spinPending) revert SpinAlreadyPending();
        if (block.timestamp < nextSpinAt()) revert SpinNotDue(nextSpinAt());
        uint256 currentPot = pot();
        if (currentPot == 0 || token.totalWeight() == 0) revert NothingToSpin();
        uint256 fee = randomness.requestFee();
        if (msg.value != fee) revert WrongFee(fee);

        lastSpinAt = block.timestamp;
        spinPending = true;
        pendingRequestedAt = block.timestamp;
        round += 1;
        uint256 requestId = randomness.requestRandomness{value: fee}();
        pendingRequestId = requestId;
        emit SpinRequested(round, requestId, currentPot);
    }

    /// @notice Called by the randomness provider. Picks the winner and pays the pot.
    function fulfillRandomness(uint256 requestId, uint256 randomWord) external {
        if (msg.sender != address(randomness)) revert OnlyRandomness();
        if (!spinPending || requestId != pendingRequestId) revert WrongRequest();
        spinPending = false;

        uint256 currentPot = pot();
        if (currentPot == 0 || token.totalWeight() == 0) {
            emit SpinRolledOver(round, currentPot);
            return;
        }

        uint256 cutoff = pendingRequestedAt;
        for (uint256 i = 0; i < MAX_DRAWS; i++) {
            address candidate = token.holderAt(uint256(keccak256(abi.encode(randomWord, i))));
            if (uint256(token.lastBuyAt(candidate)) + minHoldTime <= cutoff) {
                lastWinner = candidate;
                lastPayout = currentPot;
                totalPaidOut += currentPot;
                token.transfer(candidate, currentPot);
                emit SpinWon(round, candidate, currentPot);
                return;
            }
        }
        // Every draw landed on a wallet that bought too recently: the pot carries to the next spin.
        emit SpinRolledOver(round, currentPot);
    }

    /// @notice If the provider never answers, anyone can clear the stuck spin after REQUEST_TIMEOUT.
    function clearStuckSpin() external {
        if (!spinPending || block.timestamp < pendingRequestedAt + REQUEST_TIMEOUT) revert NotStuck();
        spinPending = false;
        emit SpinCleared(round, pendingRequestId);
    }

    /// @notice Swap the randomness provider (e.g. testnet → Chainlink). Renounce ownership to lock it.
    function setRandomness(address provider) external onlyOwner {
        if (spinPending) revert SpinAlreadyPending();
        randomness = IRandomnessProvider(provider);
        emit RandomnessSet(provider);
    }
}
