// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {GooferToken} from "../src/GooferToken.sol";
import {GooferFlywheel} from "../src/GooferFlywheel.sol";
import {ManualRandomnessProvider} from "../src/randomness/ManualRandomnessProvider.sol";
import {ChainlinkVRFProvider, VRFV2PlusClient} from "../src/randomness/ChainlinkVRFProvider.sol";

contract MockVRFCoordinator {
    uint256 public lastRequestId;
    VRFV2PlusClient.RandomWordsRequest public lastRequest;
    address public lastRequester;

    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata req) external returns (uint256) {
        lastRequest = req;
        lastRequester = msg.sender;
        return ++lastRequestId;
    }

    function fulfill(uint256 requestId, uint256 word) external {
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        ChainlinkVRFProvider(lastRequester).rawFulfillRandomWords(requestId, words);
    }
}

contract GooferTest is Test {
    uint256 constant SUPPLY = 1_000_000_000 ether;
    uint256 constant FEE_BPS = 100; // 1%
    uint256 constant INTERVAL = 3 minutes;

    GooferToken token;
    GooferFlywheel flywheel;
    ManualRandomnessProvider rng;

    address deployer = address(this);
    address pair = makeAddr("pair");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    function setUp() public {
        vm.warp(1_800_000_000);
        token = new GooferToken(SUPPLY, FEE_BPS, deployer);
        rng = new ManualRandomnessProvider();
        flywheel = new GooferFlywheel(address(token), address(rng), INTERVAL, INTERVAL);
        rng.setConsumer(address(flywheel));
        token.setFlywheel(address(flywheel));

        // Launch: liquidity goes to the pool before it's registered, so no fee is charged on it.
        token.transfer(pair, SUPPLY / 2);
        token.setPair(pair, true);
    }

    function _buy(address who, uint256 amount) internal {
        vm.prank(pair);
        token.transfer(who, amount);
    }

    function _sell(address who, uint256 amount) internal {
        vm.prank(who);
        token.transfer(pair, amount);
    }

    function _naiveHolderAt(uint256 point) internal view returns (address) {
        uint256 r = point % token.totalWeight();
        uint256 n = token.holderCount();
        for (uint256 i = 1; i <= n; i++) {
            address h = token.holderAtIndex(i);
            uint256 w = token.weightOf(h);
            if (r < w) return h;
            r -= w;
        }
        revert("unreachable");
    }

    // ---- Token -----------------------------------------------------------------------------------

    function test_FeeCapEnforced() public {
        vm.expectRevert(GooferToken.FeeTooHigh.selector);
        new GooferToken(SUPPLY, 501, deployer);
    }

    function test_BuyAndSellPayFeeToFlywheel() public {
        _buy(alice, 1000 ether);
        assertEq(token.balanceOf(alice), 990 ether);
        assertEq(flywheel.pot(), 10 ether);

        _sell(alice, 500 ether);
        assertEq(token.balanceOf(alice), 490 ether);
        assertEq(flywheel.pot(), 15 ether);
    }

    function test_WalletTransfersAreFree() public {
        token.transfer(alice, 1000 ether);
        assertEq(token.balanceOf(alice), 1000 ether);
        assertEq(flywheel.pot(), 0);
    }

    function test_PoolFlywheelAndDeadAreOffTheWheel() public {
        assertEq(token.weightOf(pair), 0);
        assertEq(token.weightOf(address(flywheel)), 0);
        token.transfer(address(0xdead), 1 ether);
        assertEq(token.weightOf(address(0xdead)), 0);
        _buy(alice, 1000 ether);
        assertEq(token.weightOf(address(flywheel)), 0);
    }

    function test_TotalWeightMatchesEligibleBalances() public {
        _buy(alice, 1000 ether);
        _buy(bob, 3000 ether);
        token.transfer(carol, 50 ether);
        uint256 expected =
            token.balanceOf(deployer) + token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(carol);
        assertEq(token.totalWeight(), expected);
    }

    function test_SellingEverythingEmptiesSlice() public {
        _buy(alice, 1000 ether);
        _sell(alice, token.balanceOf(alice));
        assertEq(token.weightOf(alice), 0);
    }

    function test_OwnerCanRenounce() public {
        token.renounceOwnership();
        vm.expectRevert();
        token.setExcluded(alice, true);
    }

    function test_FlywheelSetOnlyOnce() public {
        vm.expectRevert(GooferToken.FlywheelAlreadySet.selector);
        token.setFlywheel(alice);
    }

    function test_HolderAtIsWeighted() public {
        // Give the deployer's tokens away so the wheel is just alice (25%) and bob (75%).
        token.transfer(address(0xdead), token.balanceOf(deployer));
        token.transfer(alice, 0); // no-op
        vm.prank(pair);
        token.transfer(alice, 1000 ether);
        vm.prank(pair);
        token.transfer(bob, 3000 ether);
        uint256 total = token.totalWeight();
        assertEq(token.holderAt(0), alice);
        assertEq(token.holderAt(token.weightOf(alice) - 1), alice);
        assertEq(token.holderAt(token.weightOf(alice)), bob);
        assertEq(token.holderAt(total - 1), bob);
        assertEq(token.holderAt(total), alice); // wraps around
    }

    function testFuzz_TreeMatchesLinearScan(uint256 seed, uint8 holders, uint256 point) public {
        uint256 n = bound(holders, 1, 40);
        for (uint256 i = 0; i < n; i++) {
            address h = address(uint160(uint256(keccak256(abi.encode(seed, i))) | 1 << 150));
            uint256 amount = bound(uint256(keccak256(abi.encode(seed, i, "amt"))), 0, 1_000_000 ether);
            token.transfer(h, amount);
            if (i % 3 == 0 && amount > 0) {
                vm.prank(h);
                token.transfer(deployer, amount / 2);
            }
        }
        assertEq(token.holderAt(point), _naiveHolderAt(point));
    }

    // ---- Flywheel --------------------------------------------------------------------------------

    function _fillPot() internal {
        _buy(alice, 1000 ether);
        _buy(bob, 3000 ether);
    }

    function test_CannotSpinBeforeInterval() public {
        _fillPot();
        flywheel.spin();
        rng.fulfill(1, 0);
        _buy(alice, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(GooferFlywheel.SpinNotDue.selector, block.timestamp + INTERVAL));
        flywheel.spin();
    }

    function test_SpinPaysWholePotToWeightedWinner() public {
        _fillPot();
        vm.warp(block.timestamp + INTERVAL + 1);
        uint256 potBefore = flywheel.pot();
        flywheel.spin();
        assertTrue(flywheel.spinPending());

        uint256 word = 42;
        address expected = token.holderAt(uint256(keccak256(abi.encode(word, uint256(0)))));
        uint256 before = token.balanceOf(expected);
        rng.fulfill(1, word);

        assertEq(flywheel.pot(), 0);
        assertEq(token.balanceOf(expected), before + potBefore);
        assertEq(flywheel.lastWinner(), expected);
        assertEq(flywheel.round(), 1);
        assertFalse(flywheel.spinPending());
    }

    function test_SpinsEveryThreeMinutes() public {
        _fillPot();
        vm.warp(block.timestamp + INTERVAL);
        flywheel.spin();
        rng.fulfill(1, 7);
        assertFalse(flywheel.canSpin());

        _buy(carol, 100 ether);
        vm.warp(block.timestamp + INTERVAL - 1);
        assertFalse(flywheel.canSpin());
        vm.warp(block.timestamp + 1);
        assertTrue(flywheel.canSpin());
        flywheel.spin();
        assertEq(flywheel.round(), 2);
    }

    function test_FreshBuyerCannotWinStraightAway() public {
        // Only one wallet on the wheel, and it just bought: every draw is disqualified.
        token.transfer(address(0xdead), token.balanceOf(deployer));
        _buy(alice, 1000 ether);
        flywheel.spin();
        uint256 potBefore = flywheel.pot();
        rng.fulfill(1, 1);
        assertEq(flywheel.pot(), potBefore); // rolled over
        assertEq(flywheel.lastWinner(), address(0));

        // After holding a full interval before the next spin, alice can win.
        vm.warp(block.timestamp + INTERVAL);
        flywheel.spin();
        rng.fulfill(2, 1);
        assertEq(flywheel.lastWinner(), alice);
    }

    function test_MovingFreshBuysDoesNotResetClock() public {
        _buy(alice, 1000 ether);
        vm.prank(alice);
        token.transfer(carol, 500 ether);
        assertEq(token.lastBuyAt(carol), block.timestamp);
    }

    function test_OnlyProviderCanFulfill() public {
        _fillPot();
        flywheel.spin();
        vm.expectRevert(GooferFlywheel.OnlyRandomness.selector);
        flywheel.fulfillRandomness(1, 1);
    }

    function test_NothingToSpinWithEmptyPot() public {
        vm.expectRevert(GooferFlywheel.NothingToSpin.selector);
        flywheel.spin();
    }

    function test_StuckSpinCanBeCleared() public {
        _fillPot();
        flywheel.spin();
        vm.expectRevert(GooferFlywheel.NotStuck.selector);
        flywheel.clearStuckSpin();
        vm.warp(block.timestamp + 1 hours);
        flywheel.clearStuckSpin();
        assertFalse(flywheel.spinPending());
        flywheel.spin();
        assertEq(flywheel.round(), 2);
    }

    function test_ChainlinkProviderEndToEnd() public {
        MockVRFCoordinator coordinator = new MockVRFCoordinator();
        ChainlinkVRFProvider vrf = new ChainlinkVRFProvider(address(coordinator), bytes32("key"), 123, false);
        GooferToken t2 = new GooferToken(SUPPLY, FEE_BPS, deployer);
        GooferFlywheel f2 = new GooferFlywheel(address(t2), address(vrf), INTERVAL, 0);
        vrf.setConsumer(address(f2));
        t2.setFlywheel(address(f2));
        t2.transfer(pair, SUPPLY / 2);
        t2.setPair(pair, true);
        vm.prank(pair);
        t2.transfer(alice, 1000 ether);

        f2.spin();
        (bytes32 keyHash, uint256 subId,, uint32 gasLimit, uint32 numWords,) = coordinator.lastRequest();
        assertEq(keyHash, bytes32("key"));
        assertEq(subId, 123);
        assertEq(gasLimit, vrf.CALLBACK_GAS_LIMIT());
        assertEq(numWords, 1);

        vm.expectRevert();
        vrf.rawFulfillRandomWords(1, new uint256[](1));

        coordinator.fulfill(1, 99);
        assertEq(f2.pot(), 0);
        assertTrue(f2.lastWinner() != address(0));
    }

    function test_OnlyFlywheelCanRequestRandomness() public {
        vm.expectRevert(ManualRandomnessProvider.OnlyConsumer.selector);
        rng.requestRandomness();
    }

    function test_GasWithManyHolders() public {
        for (uint256 i = 1; i <= 2000; i++) {
            token.transfer(address(uint160(0x100000 + i)), 1000 ether);
        }
        vm.warp(block.timestamp + INTERVAL);
        uint256 g = gasleft();
        _buy(alice, 5000 ether);
        emit log_named_uint("gas: buy with 2000 holders", g - gasleft());
        g = gasleft();
        vm.prank(address(uint160(0x100000 + 7)));
        token.transfer(bob, 10 ether);
        emit log_named_uint("gas: wallet transfer to new holder", g - gasleft());

        vm.warp(block.timestamp + INTERVAL);
        g = gasleft();
        flywheel.spin();
        emit log_named_uint("gas: spin request", g - gasleft());
        g = gasleft();
        rng.fulfill(1, 123456);
        uint256 used = g - gasleft();
        emit log_named_uint("gas: pick winner + payout", used);
        assertLt(used, 300_000); // well inside the 500k VRF callback limit
    }
}
