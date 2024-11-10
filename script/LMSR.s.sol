// script/DeployLMSR.s.sol
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {LMSRMarket} from "../src/LMSR.sol";
import {MockERC20} from "../test/ERC20.m.sol";

contract DeployLMSR is Script {
    LMSRMarket public market;
    MockERC20 public usdc;

    // Configuration
    uint256 constant LIQUIDITY = 1000e18; // Initial liquidity parameter
    uint256 constant NUM_OUTCOMES = 2; // Number of outcomes in the market

    function setUp() public {
        // Any setup configuration can go here
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // For local testing, deploy a mock USDC
        // For mainnet, you'd use the real USDC address
        if (block.chainid == 31337) {
            // Local anvil chain
            usdc = new MockERC20("USDC", "USDC", 6);
            console.log("Deployed Mock USDC at:", address(usdc));

            // Mint some initial USDC for testing
            usdc.mint(msg.sender, 1000000e6); // 1M USDC
        }

        // Deploy LMSR Market
        market = new LMSRMarket(
            block.chainid == 31337 ? address(usdc) : getUSDCAddress(),
            LIQUIDITY,
            NUM_OUTCOMES
        );

        console.log("Deployed LMSR Market at:", address(market));
        console.log("USDC address:", address(market.USDC()));
        console.log("Number of outcomes:", market.numOutcomes());
        console.log("Liquidity parameter:", market.liquidity());

        vm.stopBroadcast();
    }

    function getUSDCAddress() internal view returns (address) {
        // Return appropriate USDC address for different networks
        if (block.chainid == 1) {
            // Ethereum Mainnet USDC
            return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        } else if (block.chainid == 137) {
            // Polygon Mainnet USDC
            return 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
        } else if (block.chainid == 42161) {
            // Arbitrum USDC
            return 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
        } else {
            revert("Unsupported network for USDC");
        }
    }
}
