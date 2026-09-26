// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title $GOOFER
/// @notice ERC-20 with a fixed supply and a small fee on DEX trades that feeds the Goofer Flywheel.
///         Every holder's slice of the wheel equals their balance. The contract keeps a running
///         sum tree (a Fenwick tree) of holder balances so the flywheel can pick a winner weighted
///         by holdings in O(log n), without looping over every holder.
/// @dev Owner powers exist only for launch setup (flywheel address, DEX pairs, excluded wallets).
///      The fee rate is fixed at deploy and can never change. Renounce ownership once set up.
contract GooferToken is ERC20, Ownable {
    uint256 public constant MAX_FEE_BPS = 500; // 5% hard cap
    uint256 private constant BPS = 10_000;

    /// @notice Fee on buys and sells through a registered DEX pair, in basis points. Fixed forever.
    uint256 public immutable feeBps;

    /// @notice Where trade fees go. Set once.
    address public flywheel;

    /// @notice DEX pools. Transfers to or from these are trades and pay the fee.
    mapping(address => bool) public isPair;

    /// @notice Wallets kept off the wheel (pools, the flywheel, burn addresses...).
    mapping(address => bool) public isExcluded;

    /// @notice Last time this wallet bought, or received tokens from a wallet that bought more recently.
    ///         The flywheel uses it to stop people buying just before a spin and winning straight away.
    mapping(address => uint64) public lastBuyAt;

    // ---- Holder weight tree -------------------------------------------------------------------
    address[] private _holders; // position i (1-based) is _holders[i - 1]
    mapping(address => uint256) public holderIndex; // 1-based, 0 = never on the wheel
    mapping(address => uint256) public weightOf; // current slice size (0 if excluded)
    mapping(uint256 => uint256) private _tree;
    uint256 public totalWeight;

    event FlywheelSet(address indexed flywheel);
    event PairSet(address indexed pair, bool isPair);
    event ExcludedSet(address indexed account, bool excluded);

    error FeeTooHigh();
    error FlywheelAlreadySet();
    error ZeroAddress();
    error NoWeight();

    constructor(uint256 totalSupply_, uint256 feeBps_, address initialHolder)
        ERC20("Goofer", "GOOFER")
        Ownable(msg.sender)
    {
        if (feeBps_ > MAX_FEE_BPS) revert FeeTooHigh();
        if (initialHolder == address(0)) revert ZeroAddress();
        feeBps = feeBps_;
        _setExcluded(address(0xdead), true);
        _mint(initialHolder, totalSupply_);
    }

    // ---- Launch setup (owner, until renounced) --------------------------------------------------

    function setFlywheel(address flywheel_) external onlyOwner {
        if (flywheel != address(0)) revert FlywheelAlreadySet();
        if (flywheel_ == address(0)) revert ZeroAddress();
        flywheel = flywheel_;
        _setExcluded(flywheel_, true);
        emit FlywheelSet(flywheel_);
    }

    /// @notice Register a DEX pool. Pools pay no slice and trades through them pay the fee.
    function setPair(address pair, bool value) external onlyOwner {
        if (pair == address(0)) revert ZeroAddress();
        isPair[pair] = value;
        emit PairSet(pair, value);
        _setExcluded(pair, value);
    }

    function setExcluded(address account, bool excluded) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        _setExcluded(account, excluded);
    }

    function _setExcluded(address account, bool excluded) private {
        isExcluded[account] = excluded;
        emit ExcludedSet(account, excluded);
        _syncWeight(account);
    }

    // ---- Wheel views ---------------------------------------------------------------------------

    function holderCount() external view returns (uint256) {
        return _holders.length;
    }

    /// @notice Holder at 1-based position `index` in the tree (may currently have zero weight).
    function holderAtIndex(uint256 index) external view returns (address) {
        return _holders[index - 1];
    }

    /// @notice The holder whose slice contains point `point` on a wheel of size totalWeight.
    ///         Picking `point` uniformly at random picks a holder with probability weight / totalWeight.
    function holderAt(uint256 point) external view returns (address) {
        uint256 total = totalWeight;
        if (total == 0) revert NoWeight();
        uint256 remaining = point % total;
        uint256 n = _holders.length;
        uint256 pos;
        for (uint256 step = _highestPowerOfTwo(n); step > 0; step >>= 1) {
            uint256 next = pos + step;
            if (next <= n && _tree[next] <= remaining) {
                pos = next;
                remaining -= _tree[next];
            }
        }
        return _holders[pos]; // position pos + 1, 1-based
    }

    // ---- Transfers -----------------------------------------------------------------------------

    function _update(address from, address to, uint256 value) internal override {
        bool isTrade = isPair[from] || isPair[to];
        if (isTrade && feeBps != 0 && flywheel != address(0) && value != 0) {
            uint256 fee = (value * feeBps) / BPS;
            if (fee != 0) {
                super._update(from, flywheel, fee);
                value -= fee;
            }
        }
        super._update(from, to, value);

        if (to != address(0)) {
            if (isPair[from]) {
                lastBuyAt[to] = uint64(block.timestamp);
            } else if (from != address(0) && lastBuyAt[from] > lastBuyAt[to]) {
                // Moving fresh buys to another wallet doesn't reset the clock.
                lastBuyAt[to] = lastBuyAt[from];
            }
        }

        _syncWeight(from);
        _syncWeight(to);
    }

    function _syncWeight(address account) private {
        if (account == address(0)) return;
        uint256 newWeight = isExcluded[account] ? 0 : balanceOf(account);
        uint256 oldWeight = weightOf[account];
        if (newWeight == oldWeight) return;
        weightOf[account] = newWeight;

        uint256 index = holderIndex[account];
        if (index == 0) {
            _append(account, newWeight);
        } else if (newWeight > oldWeight) {
            _add(index, newWeight - oldWeight);
        } else {
            _sub(index, oldWeight - newWeight);
        }
        totalWeight = totalWeight + newWeight - oldWeight;
    }

    // ---- Fenwick tree internals -----------------------------------------------------------------

    function _append(address account, uint256 weight) private {
        _holders.push(account);
        uint256 n = _holders.length;
        holderIndex[account] = n;
        // Node n covers positions (n - lowbit(n), n]; everything but n itself is already in the tree.
        _tree[n] = weight + _prefix(n - 1) - _prefix(n - (n & (~n + 1)));
    }

    function _add(uint256 index, uint256 delta) private {
        uint256 n = _holders.length;
        for (uint256 i = index; i <= n; i += i & (~i + 1)) {
            _tree[i] += delta;
        }
    }

    function _sub(uint256 index, uint256 delta) private {
        uint256 n = _holders.length;
        for (uint256 i = index; i <= n; i += i & (~i + 1)) {
            _tree[i] -= delta;
        }
    }

    function _prefix(uint256 index) private view returns (uint256 sum) {
        for (uint256 i = index; i > 0; i -= i & (~i + 1)) {
            sum += _tree[i];
        }
    }

    function _highestPowerOfTwo(uint256 n) private pure returns (uint256 p) {
        if (n == 0) return 0;
        p = 1;
        while (p <= n >> 1) p <<= 1;
    }
}
