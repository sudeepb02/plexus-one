// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {YieldToken} from "../src/YieldToken.sol";
import {MockYieldOracle} from "../src/mocks/MockYieldOracle.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {MockERC20} from "./mocks/MockERC20.sol";

contract YieldTokenTest is Test {
    YieldToken yt;
    MockERC20 underlying;
    MockYieldOracle oracle;

    address user = address(0x1);
    address liquidator = address(0x2);

    uint256 maturity;

    function setUp() public {
        underlying = new MockERC20("Mock USDC", "mockUSDC", 6);
        oracle = new MockYieldOracle();
        oracle.setRate(0.05e18); // Default 5% APY

        maturity = block.timestamp + 365 days;
        yt = new YieldToken("USDC Yield Token", "ytUSDC", address(underlying), maturity);

        yt.setOracle(address(oracle));

        // Mint underlying to user and liquidator
        underlying.mint(user, 100_000 * 1e6);
        underlying.mint(liquidator, 100_000 * 1e6);

        vm.prank(user);
        underlying.approve(address(yt), type(uint256).max);

        vm.prank(liquidator);
        underlying.approve(address(yt), type(uint256).max);
    }

    function test_MintSynthetic() public {
        uint256 collateral = 10_000 * 1e6;
        uint256 ytTokens = 80_000 * 1e6;

        // Deposit 10k USDC, Mint 80k YT
        vm.prank(user);
        yt.mintSynthetic(collateral, ytTokens);

        (uint256 vCollateral, uint256 vDebt) = yt.vaults(user);
        assertEq(vCollateral, collateral);
        assertEq(vDebt, ytTokens);
        assertEq(yt.balanceOf(user), ytTokens);
    }

    function test_DebtAccumulation() public {
        vm.prank(user);
        yt.mintSynthetic(100_000 * 1e6, 100_000 * 1e6);

        // Set Oracle Rate to 10% APY
        oracle.setRate(0.1e18);

        // Advance time by 1 year - 1 second (just before maturity)
        vm.warp(maturity - 1);

        // update global index
        yt.updateGlobalIndex();

        // Expected Index:
        // Start = 1e18
        // Rate = 0.1e18
        // Time = ~1 year
        // Interest ~= 0.1e18
        // New Index ~= 1.1e18

        assertApproxEqRel(yt.globalIndex(), 1.1e18, 1e14); // 0.01% tolerance
    }

    function test_Liquidation() public {
        // Collateral: 15000 usdc. Debt: 100,000 USDC.
        // Required Margin (10%): 10k, position is solvent
        vm.prank(user);
        yt.mintSynthetic(15_000 * 1e6, 100_000 * 1e6);

        // Rate = 10% APY.
        oracle.setRate(0.1e18);

        // Advance ~6+ months.
        vm.warp(190 days);

        // Update Index
        yt.updateGlobalIndex();

        // Debt Value (Accrued Yield) = 100k * 0.1 * 0.5 (half year) = 5k.
        // Liability = Debt Value (~5k) + Margin (10k) = 15k+.
        // Collateral = 15k, position is insolvent
        assertFalse(yt.isSolvent(user));

        // Liquidator mints YT to have funds to liquidate
        vm.prank(liquidator);
        yt.mintSynthetic(100_000 * 1e6, 100_000 * 1e6);

        uint256 debtToLiquidate = 100_000 * 1e6;

        // Reward Calculation:
        // Accrued Value of 100k YT = 100k * 0.1 * 0.5 = 5k usdc.
        // Liquidation Reward = 5% of 5k = 250 usdc.
        // Total underlying amount received after liquidation = 5.25k usdc.

        uint256 balBefore = underlying.balanceOf(liquidator);

        vm.prank(liquidator);
        yt.liquidate(user, debtToLiquidate);

        uint256 balAfter = underlying.balanceOf(liquidator);

        assertApproxEqAbs(balAfter - balBefore, 5250 * 1e6, 1e14); // 0.01%

        (uint256 vCol, uint256 vDebt) = yt.vaults(user);
        assertApproxEqAbs(vCol, 15_000 * 1e6 - 5250 * 1e6, 1e14);
        assertEq(vDebt, 0);

        vm.stopPrank();
    }

    function test_Settlement() public {
        // Mint 100k YT with 20k Collateral
        vm.prank(user);
        yt.mintSynthetic(20_000 * 1e6, 100_000 * 1e6);

        // Rate 10%
        oracle.setRate(0.1e18);
        vm.warp(maturity + 1); // Go past maturity

        // 1. User Settle Short
        // Index calculation:
        // Time delta = Maturity - Start (1 year)
        // Rate = 10%
        // Index = 1.1e18

        // Debt (Accrued Yield) = 100 * (1.1 - 1.0) = 10 usdc.
        // Collateral = 20.
        // Refund = 20 - 10 = 10.

        uint256 balBefore = underlying.balanceOf(user);

        vm.prank(user);
        yt.settleShort();

        uint256 balAfter = underlying.balanceOf(user);

        assertEq(balAfter - balBefore, 10_000 * 1e6);

        // 2. User Redeem Yield (Long) - User holds the 100 YT they minted
        // Payout = 100k * (1.1 - 1.0) = 10k usdc.

        balBefore = underlying.balanceOf(user);

        vm.prank(user);
        yt.redeemYield(100_000 * 1e6);

        balAfter = underlying.balanceOf(user);
        assertEq(balAfter - balBefore, 10_000 * 1e6);
    }
}
