// test/LMSRMarket.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/LMSR.sol";
import {MockERC20} from "./ERC20.m.sol";

contract LMSRMarketTest is Test {
    LMSRMarket public market;
    MockERC20 public usdc;

    address alice = address(0x1);
    address bob = address(0x2);

    uint256 constant INITIAL_BALANCE = 1000000e6; // 1M USDC
    uint256 constant LIQUIDITY = 1000e18;
    uint256 constant NUM_OUTCOMES = 2;

    function setUp() public {
        // Deploy mock USDC
        usdc = new MockERC20("USDC", "USDC", 6);

        // Deploy market
        market = new LMSRMarket(address(usdc), LIQUIDITY, NUM_OUTCOMES);

        // Setup test accounts
        vm.startPrank(alice);
        usdc.mint(alice, INITIAL_BALANCE);
        usdc.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.mint(bob, INITIAL_BALANCE);
        usdc.approve(address(market), type(uint256).max);
        vm.stopPrank();
    }

    function test_InitialState() public view {
        assertEq(market.numOutcomes(), NUM_OUTCOMES);
        assertEq(market.liquidity(), LIQUIDITY);
        assertEq(address(market.USDC()), address(usdc));
        assertEq(market.resolved(), false);
    }

    function test_BuyShares() public {
        vm.startPrank(alice);

        uint256 amount = 100e6; // 100 USDC worth
        uint256 outcome = 0;

        uint256 cost = market.calculateCost(outcome, amount);
        uint256 balanceBefore = usdc.balanceOf(alice);

        market.buyShares(outcome, amount);

        assertEq(usdc.balanceOf(alice), balanceBefore - cost);
        assertEq(market.getUserPosition(alice, outcome), amount);
        assertEq(market.quantities(outcome), amount);
    }

    function test_RevertWhenBuyingAfterResolution() public {
        // Resolve market first
        market.resolveMarket(0);

        vm.startPrank(alice);
        vm.expectRevert(MarketAlreadyResolved.selector);
        market.buyShares(0, 100e6);
    }

    function test_ClaimWinnings() public {
        uint256 amount = 100e6;
        uint256 outcome = 0;

        // Buy shares
        vm.startPrank(alice);
        market.buyShares(outcome, amount);

        // Resolve market
        vm.stopPrank();
        market.resolveMarket(outcome);

        // Claim winnings
        vm.startPrank(alice);
        uint256 balanceBefore = usdc.balanceOf(alice);
        market.claimWinnings(amount);

        uint256 expectedPayout = (amount * market.SCALE()) / (10 ** (18 - market.USDC_DECIMALS()));
        assertEq(usdc.balanceOf(alice), balanceBefore + expectedPayout);
        assertEq(market.getUserPosition(alice, outcome), 0);
    }

    function test_RevertWhenClaimingBeforeResolution() public {
        vm.startPrank(alice);
        market.buyShares(0, 100e6);

        vm.expectRevert(MarketNotResolved.selector);
        market.claimWinnings(100e6);
    }
}
