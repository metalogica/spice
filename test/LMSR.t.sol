// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "@forge-std/Test.sol";
import { console } from "@forge-std/console.sol";
import "../src/LMSR.sol";
import {MockERC20} from "./ERC20.m.sol";

contract LMSRMarketTest is Test {
    LMSRMarket public market;
    MockERC20 public usdc;

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    uint256 constant INITIAL_BALANCE = 1_000_000e6;
    uint256 constant LIQUIDITY = 1000e18;
    uint256 constant NUM_OUTCOMES = 2;

    function setUp() public {
        // Deploy mock USDC
        usdc = new MockERC20("USDC", "USDC", 6);

        // Deploy market
        market = new LMSRMarket(address(usdc), LIQUIDITY, NUM_OUTCOMES);

        // Setup test accounts
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            usdc.mint(users[i], INITIAL_BALANCE);
            usdc.approve(address(market), type(uint256).max);
            vm.stopPrank();
        }
    }

    function exp(uint256 x) internal pure returns (uint256) {
        return x + 1e18; // Same as contract's implementation
    }

    function getProbabilities() internal view returns (uint256[] memory) {
        uint256[] memory probs = new uint256[](market.numOutcomes());

        // Calculate total exponential sum for denominator
        uint256 totalSum = 0;
        for (uint256 i = 0; i < market.numOutcomes(); i++) {
            uint256 quantity = market.quantities(i);
            totalSum += exp((quantity * market.SCALE()) / market.liquidity());
        }

        // Calculate probability for each outcome
        for (uint256 i = 0; i < market.numOutcomes(); i++) {
            uint256 quantity = market.quantities(i);
            uint256 expTerm = exp((quantity * market.SCALE()) / market.liquidity());
            probs[i] = (expTerm * market.SCALE()) / totalSum;
        }

        return probs;
    }

    function test_InitialState() public view {
        assertEq(market.numOutcomes(), NUM_OUTCOMES);
        assertEq(market.liquidity(), LIQUIDITY);
        assertEq(address(market.USDC()), address(usdc));
        assertEq(market.resolved(), false);

        // Check initial probabilities are equal
        uint256[] memory probs = getProbabilities();
        for (uint256 i = 0; i < NUM_OUTCOMES; i++) {
            assertApproxEqRel(probs[i], 0.5e18, 0.01e18); // 1% tolerance
        }
    }

    function test_BuyShares() public {
        vm.startPrank(alice);

        uint256 amount = 100e6; // 100 USDC worth
        uint256 outcome = 0;

        uint256 cost = market.calculateCost(outcome, amount);
        uint256 balanceBefore = usdc.balanceOf(alice);
        uint256[] memory probsBefore = getProbabilities();

        market.buyShares(outcome, amount);

        // Check balance and position updates
        assertEq(usdc.balanceOf(alice), balanceBefore - cost);
        assertEq(market.getUserPosition(alice, outcome), amount);
        assertEq(market.quantities(outcome), amount);

        // Check probability changes
        uint256[] memory probsAfter = getProbabilities();
        assertTrue(probsAfter[outcome] > probsBefore[outcome], "Probability should increase");
        assertTrue(probsAfter[1 - outcome] < probsBefore[1 - outcome], "Other outcome prob should decrease");
    }

    function test_MultipleBuyers() public {
        uint256 amount = 100e6;

        // Alice buys outcome 0
        vm.prank(alice);
        market.buyShares(0, amount);

        // Bob buys outcome 1
        vm.prank(bob);
        market.buyShares(1, amount);

        assertEq(market.getUserPosition(alice, 0), amount);
        assertEq(market.getUserPosition(bob, 1), amount);

        uint256[] memory probs = getProbabilities();
        assertApproxEqRel(probs[0], probs[1], 0.01e18); // Should be roughly equal
    }

    function test_RevertWhenBuyingAfterResolution() public {
        market.resolveMarket(0);

        vm.startPrank(alice);
        vm.expectRevert(MarketAlreadyResolved.selector);
        market.buyShares(0, 100e6);
    }

    function test_ClaimWinnings() public {
        uint256 amount = 100e6;
        uint256 outcome = 0;

        // Alice and Bob buy shares
        vm.prank(alice);
        market.buyShares(outcome, amount);

        vm.prank(bob);
        market.buyShares(1, amount);

        // Resolve market with outcome 0
        market.resolveMarket(outcome);

        // Alice claims winnings (winner)
        vm.startPrank(alice);
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        market.claimWinnings(amount);

        uint256 expectedPayout = (amount * market.SCALE()) / (10 ** (18 - market.USDC_DECIMALS()));
        assertEq(usdc.balanceOf(alice), aliceBalanceBefore + expectedPayout);
        assertEq(market.getUserPosition(alice, outcome), 0);

        // Bob tries to claim (loser)
        vm.startPrank(bob);
        uint256 bobBalanceBefore = usdc.balanceOf(bob);
        market.claimWinnings(amount);
        assertEq(usdc.balanceOf(bob), bobBalanceBefore, "Losing position should pay nothing");
    }

    function test_RevertWhenClaimingBeforeResolution() public {
        vm.startPrank(alice);
        market.buyShares(0, 100e6);

        vm.expectRevert(MarketNotResolved.selector);
        market.claimWinnings(100e6);
    }

    function test_RevertInvalidOutcome() public {
        vm.startPrank(alice);
        vm.expectRevert(InvalidOutcome.selector);
        market.buyShares(NUM_OUTCOMES, 100e6); // Invalid outcome index
    }

    function test_RevertInsufficientBalance() public {
        vm.startPrank(charlie);
        usdc.transfer(alice, INITIAL_BALANCE); // Transfer all balance away

        vm.expectRevert();
        market.buyShares(0, 100e6);
    }

    function test_GetProbabilities() public {
        vm.startPrank(alice);
        usdc.mint(alice, 10_000_000e6);
        usdc.approve(address(market), type(uint256).max);
        vm.stopPrank();

        // Buy a large amount of outcome 0 to skew probabilities
        vm.prank(alice);
        console.log('pre purchase cost: ', market.calculateCost(0, 1e6));

        market.buyShares(0, 1e6);

        console.log('post purchase cost: ', market.calculateCost(0, 1e6));

        uint256[] memory probs = getProbabilities();
        console.log("prob: ", probs[0]);
        console.log("prob: ", probs[1]);

        assertTrue(probs[0] > 0.75e18, "Probability should be heavily skewed");
        assertTrue(probs[1] < 0.25e18, "Other outcome should have low probability");

        // Sum of probabilities should equal 1
        assertApproxEqRel(probs[0] + probs[1], 1e18, 0.01e18);
    }
}
