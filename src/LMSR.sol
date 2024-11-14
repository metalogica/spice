// src/LMSRMarket.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";
import { UD60x18, ud, unwrap, ln, exp, div, mul } from "@prb-math/UD60x18.sol";
import { console } from "@forge-std/console.sol";

interface IUSDC is IERC20 {
    function decimals() external view returns (uint8);
}

error InvalidOutcome();
error MarketAlreadyResolved();
error MarketNotResolved();
error AmountTooSmall();
error InsufficientShares();
error InvalidUSDCAddress();
error InvalidUSDCDecimals();
error TransferFailed();
error InsufficientUSDC();

contract LMSRMarket is ReentrancyGuard {
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    IUSDC public immutable USDC;
    uint8 public constant USDC_DECIMALS = 6;
    uint256 public constant SCALE = 1e6;
    uint256 public constant MIN_AMOUNT = 1e6; // 1 USDC minimum

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    uint256 public immutable liquidity; // b parameter in LMSR
    uint256[] public quantities; // quantity of each outcome token
    uint256 public immutable numOutcomes;
    bool public resolved;
    uint256 public winningOutcome;

    mapping(address => mapping(uint256 => uint256)) public userShares;
    uint256 public totalPoolValue;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event SharesPurchased(address indexed buyer, uint256 indexed outcome, uint256 amount, uint256 usdcCost);

    event SharesSold(address indexed seller, uint256 indexed outcome, uint256 amount, uint256 usdcPayout);

    event MarketResolved(uint256 indexed outcome);

    event LiquidityAdded(address indexed provider, uint256 amount);
    event LiquidityRemoved(address indexed provider, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _usdc, uint256 _liquidity, uint256 _numOutcomes) {
        if (_numOutcomes < 2) revert InvalidOutcome();
        if (_usdc == address(0)) revert InvalidUSDCAddress();

        USDC = IUSDC(_usdc);
        if (USDC.decimals() != USDC_DECIMALS) revert InvalidUSDCDecimals();

        liquidity = _liquidity;
        numOutcomes = _numOutcomes;

        // Initialize quantities
        for (uint256 i = 0; i < _numOutcomes; i++) {
            quantities.push(0);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function calculateCost(uint256 outcome, uint256 amount) public view returns (uint256 cost) {
        if (outcome >= numOutcomes) revert InvalidOutcome();
        if (amount < MIN_AMOUNT) revert AmountTooSmall();

        uint256[] memory newQuantities = new uint256[](numOutcomes);
        for (uint256 i = 0; i < numOutcomes; i++) {
            newQuantities[i] = quantities[i];
        }

        newQuantities[outcome] += amount;

        uint256 newCost = calculateLMSRCost(newQuantities);
        console.log('newCost: ', newCost);

        uint256 currentCost = calculateLMSRCost(quantities);
        console.log('currenCost: ', currentCost);

        cost = newCost > currentCost ? newCost - currentCost : 0;
    }

    function buyShares(uint256 outcome, uint256 amount) external nonReentrant {
        if (resolved) revert MarketAlreadyResolved();
        if (outcome >= numOutcomes) revert InvalidOutcome();
        if (amount < MIN_AMOUNT) revert AmountTooSmall();

        uint256 cost = calculateCost(outcome, amount);
        console.log(cost);

        bool success = USDC.transferFrom(msg.sender, address(this), cost);
        if (!success) revert TransferFailed();

        quantities[outcome] += amount;
        userShares[msg.sender][outcome] += amount;
        totalPoolValue += cost;

        emit SharesPurchased(msg.sender, outcome, amount, cost);
    }

    function resolveMarket(uint256 _winningOutcome) external {
        if (resolved) revert MarketAlreadyResolved();
        if (_winningOutcome >= numOutcomes) revert InvalidOutcome();

        resolved = true;
        winningOutcome = _winningOutcome;

        emit MarketResolved(_winningOutcome);
    }

    function claimWinnings(uint256 amount) external nonReentrant {
        if (!resolved) revert MarketNotResolved();
        if (userShares[msg.sender][winningOutcome] < amount) {
            revert InsufficientShares();
        }

        uint256 usdcAmount = (amount * SCALE) / (10 ** (18 - USDC_DECIMALS));
        if (usdcAmount > USDC.balanceOf(address(this))) {
            revert InsufficientUSDC();
        }

        userShares[msg.sender][winningOutcome] -= amount;
        quantities[winningOutcome] -= amount;
        totalPoolValue -= usdcAmount;

        bool success = USDC.transfer(msg.sender, usdcAmount);
        if (!success) revert TransferFailed();

        emit SharesSold(msg.sender, winningOutcome, amount, usdcAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getUserPosition(address user, uint256 outcome) external view returns (uint256) {
        return userShares[user][outcome];
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function calculateLMSRCost(uint256[] memory _quantities) public view returns (uint256) {
        require(_quantities.length == numOutcomes, "Quantities length mismatch");

        UD60x18 sum = ud(0);

        for (uint256 i = 0; i < numOutcomes; i++) {
            // Convert quantity to UD60x18, ensuring proper scaling
            UD60x18 qi = ud(_quantities[i]);

            // Calculate qi / b
            UD60x18 qi_div_b = qi.div(ud(liquidity));

            // Calculate exp(qi / b)
            UD60x18 exp_qi_div_b = qi_div_b.exp();

            // Sum up the exponentials
            sum = sum.add(exp_qi_div_b);
        }

        // Calculate ln(sum)
        UD60x18 ln_sum = sum.ln();

        // Multiply by liquidity (b)
        UD60x18 cost = ud(liquidity).mul(ln_sum);

        // Return the cost as uint256 (unwrap the UD60x18)
        return unwrap(cost);
    }
}
