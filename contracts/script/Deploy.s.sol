// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {GooferToken} from "../src/GooferToken.sol";
import {GooferFlywheel} from "../src/GooferFlywheel.sol";
import {ManualRandomnessProvider} from "../src/randomness/ManualRandomnessProvider.sol";
import {ChainlinkVRFProvider} from "../src/randomness/ChainlinkVRFProvider.sol";

/// @notice Deploys $GOOFER, the flywheel and a randomness provider, and wires them together.
///
///   RANDOMNESS=manual     testnet only: your keeper supplies the random numbers
///   RANDOMNESS=chainlink  Chainlink VRF v2.5 (needs VRF_COORDINATOR, VRF_KEY_HASH, VRF_SUBSCRIPTION_ID)
///
/// All tokens go to the deployer, who then adds liquidity and calls setPair (see README).
contract Deploy is Script {
    function run() external {
        uint256 supply = vm.envOr("TOTAL_SUPPLY", uint256(1_000_000_000)) * 1e18;
        uint256 feeBps = vm.envOr("FEE_BPS", uint256(100));
        uint256 spinInterval = vm.envOr("SPIN_INTERVAL", uint256(3 minutes));
        uint256 minHold = vm.envOr("MIN_HOLD", uint256(3 minutes));
        string memory mode = vm.envOr("RANDOMNESS", string("manual"));
        bool useChainlink = keccak256(bytes(mode)) == keccak256("chainlink");

        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        GooferToken token = new GooferToken(supply, feeBps, deployer);

        address provider;
        if (useChainlink) {
            ChainlinkVRFProvider vrf = new ChainlinkVRFProvider(
                vm.envAddress("VRF_COORDINATOR"),
                vm.envBytes32("VRF_KEY_HASH"),
                vm.envUint("VRF_SUBSCRIPTION_ID"),
                vm.envOr("VRF_NATIVE_PAYMENT", false)
            );
            provider = address(vrf);
        } else {
            require(block.chainid != 1, "Manual randomness is testnet only. Use RANDOMNESS=chainlink on mainnet.");
            provider = address(new ManualRandomnessProvider());
        }

        GooferFlywheel flywheel = new GooferFlywheel(address(token), provider, spinInterval, minHold);
        token.setFlywheel(address(flywheel));
        if (useChainlink) ChainlinkVRFProvider(provider).setConsumer(address(flywheel));
        else ManualRandomnessProvider(provider).setConsumer(address(flywheel));

        vm.stopBroadcast();

        console.log("GooferToken     ", address(token));
        console.log("GooferFlywheel  ", address(flywheel));
        console.log("Randomness      ", provider, useChainlink ? "(Chainlink VRF)" : "(manual, TESTNET ONLY)");
        console.log("Spin interval s ", spinInterval);
    }
}
