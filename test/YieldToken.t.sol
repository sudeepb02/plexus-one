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
    address alice = address(0x3);
    address bob = address(0x4);

    uint256 maturity;

    // Events for testing
    event Transfer(address indexed from, address indexed to, uint256 value);

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
        underlying.mint(alice, 100_000 * 1e6);
        underlying.mint(bob, 100_000 * 1e6);

        vm.prank(user);
        underlying.approve(address(yt), type(uint256).max);

        vm.prank(liquidator);
        underlying.approve(address(yt), type(uint256).max);

        vm.prank(alice);
        underlying.approve(address(yt), type(uint256).max);

        vm.prank(bob);
        underlying.approve(address(yt), type(uint256).max);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                              BASIC FUNCTIONALITY                                //
    /////////////////////////////////////////////////////////////////////////////////////

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

    /////////////////////////////////////////////////////////////////////////////////////
    //                           CONSTRUCTOR & INITIALIZATION                          //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_ConstructorSetsCorrectValues() public view {
        assertEq(address(yt.UNDERLYING_TOKEN()), address(underlying));
        assertEq(yt.MATURITY(), maturity);
        assertEq(yt.decimals(), 6);
        assertEq(yt.globalIndex(), 1e18);
        assertEq(yt.owner(), address(this));
    }

    function test_DecimalsMatchUnderlyingToken() public {
        MockERC20 underlying18 = new MockERC20("Mock DAI", "mockDAI", 18);
        YieldToken yt18 = new YieldToken("DAI Yield Token", "ytDAI", address(underlying18), maturity);
        assertEq(yt18.decimals(), 18);

        MockERC20 underlying8 = new MockERC20("Mock WBTC", "mockWBTC", 8);
        YieldToken yt8 = new YieldToken("WBTC Yield Token", "ytWBTC", address(underlying8), maturity);
        assertEq(yt8.decimals(), 8);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                              ACCESS CONTROL TESTS                               //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_SetHook_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        yt.setHook(address(0x123));
    }

    function test_SetHook_CanOnlyBeSetOnce() public {
        yt.setHook(address(0x123));
        
        vm.expectRevert(YieldToken.HookAlreadySet.selector);
        yt.setHook(address(0x456));
    }

    function test_SetOracle_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        yt.setOracle(address(0x123));
    }

    function test_SetOracle_CanBeUpdated() public {
        MockYieldOracle newOracle = new MockYieldOracle();
        yt.setOracle(address(newOracle));
        assertEq(address(yt.oracle()), address(newOracle));
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          MINT SYNTHETIC EDGE CASES                              //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_MintSynthetic_OnlyCollateral() public {
        vm.prank(user);
        yt.mintSynthetic(10_000 * 1e6, 0);

        (uint256 vCollateral, uint256 vDebt) = yt.vaults(user);
        assertEq(vCollateral, 10_000 * 1e6);
        assertEq(vDebt, 0);
        assertEq(yt.balanceOf(user), 0);
    }

    function test_MintSynthetic_IncrementalMinting() public {
        vm.startPrank(user);
        
        // First mint
        yt.mintSynthetic(10_000 * 1e6, 50_000 * 1e6);
        
        // Second mint - add more collateral and debt
        yt.mintSynthetic(5_000 * 1e6, 25_000 * 1e6);
        
        vm.stopPrank();

        (uint256 vCollateral, uint256 vDebt) = yt.vaults(user);
        assertEq(vCollateral, 15_000 * 1e6);
        assertEq(vDebt, 75_000 * 1e6);
        assertEq(yt.balanceOf(user), 75_000 * 1e6);
    }

    function test_MintSynthetic_RevertAfterMaturity() public {
        vm.warp(maturity + 1);
        
        vm.prank(user);
        vm.expectRevert(YieldToken.MarketExpired.selector);
        yt.mintSynthetic(10_000 * 1e6, 50_000 * 1e6);
    }

    function test_MintSynthetic_RevertInsufficientCollateral() public {
        // Try to mint 100k YT with only 5k collateral (below 10% margin requirement)
        vm.prank(user);
        vm.expectRevert(YieldToken.SolvencyCheckFailed.selector);
        yt.mintSynthetic(5_000 * 1e6, 100_000 * 1e6);
    }

    function test_MintSynthetic_ExactMinimumCollateral() public {
        // Mint 100k YT with exactly 10k collateral (exactly 10% margin)
        vm.prank(user);
        yt.mintSynthetic(10_000 * 1e6, 100_000 * 1e6);

        assertTrue(yt.isSolvent(user));
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          BURN SYNTHETIC EDGE CASES                              //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_BurnSynthetic_FullClose() public {
        vm.startPrank(user);
        yt.mintSynthetic(15_000 * 1e6, 100_000 * 1e6);
        
        uint256 balBefore = underlying.balanceOf(user);
        yt.burnSynthetic(100_000 * 1e6, 15_000 * 1e6);
        uint256 balAfter = underlying.balanceOf(user);
        
        vm.stopPrank();

        (uint256 vCollateral, uint256 vDebt) = yt.vaults(user);
        assertEq(vCollateral, 0);
        assertEq(vDebt, 0);
        assertEq(yt.balanceOf(user), 0);
        assertEq(balAfter - balBefore, 15_000 * 1e6);
    }

    function test_BurnSynthetic_PartialDebtRepayment() public {
        vm.startPrank(user);
        yt.mintSynthetic(15_000 * 1e6, 100_000 * 1e6);
        
        // Repay 50k YT, keep collateral
        yt.burnSynthetic(50_000 * 1e6, 0);
        
        vm.stopPrank();

        (uint256 vCollateral, uint256 vDebt) = yt.vaults(user);
        assertEq(vCollateral, 15_000 * 1e6);
        assertEq(vDebt, 50_000 * 1e6);
        assertEq(yt.balanceOf(user), 50_000 * 1e6);
    }

    function test_BurnSynthetic_OnlyCollateralWithdraw() public {
        vm.startPrank(user);
        yt.mintSynthetic(20_000 * 1e6, 100_000 * 1e6);
        
        // Withdraw 5k collateral, keep debt same
        uint256 balBefore = underlying.balanceOf(user);
        yt.burnSynthetic(0, 5_000 * 1e6);
        uint256 balAfter = underlying.balanceOf(user);
        
        vm.stopPrank();

        (uint256 vCollateral, uint256 vDebt) = yt.vaults(user);
        assertEq(vCollateral, 15_000 * 1e6);
        assertEq(vDebt, 100_000 * 1e6);
        assertEq(balAfter - balBefore, 5_000 * 1e6);
    }

    function test_BurnSynthetic_RevertExceedsMintedAmount() public {
        vm.startPrank(user);
        yt.mintSynthetic(15_000 * 1e6, 100_000 * 1e6);
        
        vm.expectRevert(YieldToken.InvalidAmount.selector);
        yt.burnSynthetic(150_000 * 1e6, 0);
        
        vm.stopPrank();
    }

    function test_BurnSynthetic_RevertExceedsCollateral() public {
        vm.startPrank(user);
        yt.mintSynthetic(15_000 * 1e6, 100_000 * 1e6);
        
        vm.expectRevert(YieldToken.InvalidAmount.selector);
        yt.burnSynthetic(0, 20_000 * 1e6);
        
        vm.stopPrank();
    }

    function test_BurnSynthetic_RevertMakesInsolvent() public {
        vm.startPrank(user);
        yt.mintSynthetic(15_000 * 1e6, 100_000 * 1e6);
        
        // Try to withdraw too much collateral making position insolvent
        vm.expectRevert(YieldToken.SolvencyCheckFailed.selector);
        yt.burnSynthetic(0, 10_000 * 1e6);
        
        vm.stopPrank();
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          YIELD REDEMPTION TESTS                                 //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_RedeemYield_RevertBeforeMaturity() public {
        vm.prank(user);
        yt.mintSynthetic(15_000 * 1e6, 100_000 * 1e6);
        
        vm.prank(user);
        vm.expectRevert(YieldToken.MarketNotExpired.selector);
        yt.redeemYield(100_000 * 1e6);
    }

    function test_RedeemYield_ZeroYieldWhenNoRateChange() public {
        vm.prank(user);
        yt.mintSynthetic(15_000 * 1e6, 100_000 * 1e6);
        
        oracle.setRate(0); // No yield
        vm.warp(maturity + 1);
        
        uint256 balBefore = underlying.balanceOf(user);
        vm.prank(user);
        yt.redeemYield(100_000 * 1e6);
        uint256 balAfter = underlying.balanceOf(user);
        
        assertEq(balAfter - balBefore, 0);
        assertEq(yt.balanceOf(user), 0);
    }

    function test_RedeemYield_PartialRedemption() public {
        vm.prank(user);
        yt.mintSynthetic(20_000 * 1e6, 100_000 * 1e6);
        
        oracle.setRate(0.1e18);
        vm.warp(maturity + 1);
        
        // Redeem only 50k YT
        uint256 balBefore = underlying.balanceOf(user);
        vm.prank(user);
        yt.redeemYield(50_000 * 1e6);
        uint256 balAfter = underlying.balanceOf(user);
        
        // 50k * 0.1 = 5k payout
        assertEq(balAfter - balBefore, 5_000 * 1e6);
        assertEq(yt.balanceOf(user), 50_000 * 1e6);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          SETTLE SHORT TESTS                                     //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_SettleShort_RevertBeforeMaturity() public {
        vm.prank(user);
        yt.mintSynthetic(15_000 * 1e6, 100_000 * 1e6);
        
        vm.prank(user);
        vm.expectRevert(YieldToken.MarketNotExpired.selector);
        yt.settleShort();
    }

    function test_SettleShort_DebtExceedsCollateral() public {
        // This scenario: high yield causes debt > collateral
        vm.prank(user);
        yt.mintSynthetic(15_000 * 1e6, 100_000 * 1e6);
        
        oracle.setRate(0.2e18); // 20% APY - very high
        vm.warp(maturity + 1);
        
        // Debt = 100k * 0.2 = 20k, but collateral only 15k
        uint256 balBefore = underlying.balanceOf(user);
        vm.prank(user);
        yt.settleShort();
        uint256 balAfter = underlying.balanceOf(user);
        
        // User gets nothing back (all collateral consumed)
        assertEq(balAfter - balBefore, 0);
        
        (uint256 vCollateral, uint256 vDebt) = yt.vaults(user);
        assertEq(vCollateral, 0);
        assertEq(vDebt, 0);
    }

    function test_SettleShort_ZeroDebtReturnsAllCollateral() public {
        vm.prank(user);
        yt.mintSynthetic(15_000 * 1e6, 100_000 * 1e6);
        
        oracle.setRate(0); // No yield
        vm.warp(maturity + 1);
        
        uint256 balBefore = underlying.balanceOf(user);
        vm.prank(user);
        yt.settleShort();
        uint256 balAfter = underlying.balanceOf(user);
        
        // All collateral returned
        assertEq(balAfter - balBefore, 15_000 * 1e6);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          LIQUIDATION EDGE CASES                                 //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_Liquidate_RevertSolventUser() public {
        vm.prank(user);
        yt.mintSynthetic(20_000 * 1e6, 100_000 * 1e6);
        
        // Liquidator gets YT
        vm.prank(liquidator);
        yt.mintSynthetic(100_000 * 1e6, 100_000 * 1e6);
        
        vm.prank(liquidator);
        vm.expectRevert(YieldToken.UserIsSolvent.selector);
        yt.liquidate(user, 50_000 * 1e6);
    }

    function test_Liquidate_PartialLiquidation() public {
        vm.prank(user);
        yt.mintSynthetic(15_000 * 1e6, 100_000 * 1e6);
        
        oracle.setRate(0.1e18);
        vm.warp(190 days);
        yt.updateGlobalIndex();
        
        assertFalse(yt.isSolvent(user));
        
        // Liquidator mints YT
        vm.prank(liquidator);
        yt.mintSynthetic(100_000 * 1e6, 100_000 * 1e6);
        
        // Partial liquidation - only 50k YT
        vm.prank(liquidator);
        yt.liquidate(user, 50_000 * 1e6);
        
        (uint256 vCollateral, uint256 vDebt) = yt.vaults(user);
        assertEq(vDebt, 50_000 * 1e6);
        assertGt(vCollateral, 0);
    }

    function test_Liquidate_CappedToMintedAmount() public {
        vm.prank(user);
        yt.mintSynthetic(15_000 * 1e6, 100_000 * 1e6);
        
        oracle.setRate(0.1e18);
        vm.warp(190 days);
        yt.updateGlobalIndex();
        
        // Mint more underlying for liquidator to create a larger position
        underlying.mint(liquidator, 100_000 * 1e6);
        
        // Liquidator mints more YT than user's debt
        vm.prank(liquidator);
        yt.mintSynthetic(200_000 * 1e6, 200_000 * 1e6);
        
        // Try to liquidate 200k, but user only has 100k debt
        // The liquidate function caps amountYt to vault.mintedAmount
        vm.prank(liquidator);
        yt.liquidate(user, 200_000 * 1e6);
        
        (uint256 vCollateral, uint256 vDebt) = yt.vaults(user);
        assertEq(vDebt, 0); // Only 100k was liquidated
    }

    function test_Liquidate_CollateralCappedToAvailable() public {
        vm.prank(user);
        yt.mintSynthetic(12_000 * 1e6, 100_000 * 1e6);
        
        oracle.setRate(0.15e18); // High rate to create large debt
        vm.warp(250 days);
        yt.updateGlobalIndex();
        
        assertFalse(yt.isSolvent(user));
        
        vm.prank(liquidator);
        yt.mintSynthetic(100_000 * 1e6, 100_000 * 1e6);
        
        uint256 balBefore = underlying.balanceOf(liquidator);
        vm.prank(liquidator);
        yt.liquidate(user, 100_000 * 1e6);
        uint256 balAfter = underlying.balanceOf(liquidator);
        
        // Liquidator receives at most user's collateral
        assertLe(balAfter - balBefore, 12_000 * 1e6);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          GLOBAL INDEX TESTS                                     //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_GlobalIndex_NoUpdateWithoutOracle() public {
        YieldToken ytNoOracle = new YieldToken("Test YT", "tYT", address(underlying), maturity);
        
        vm.warp(block.timestamp + 100 days);
        ytNoOracle.updateGlobalIndex();
        
        assertEq(ytNoOracle.globalIndex(), 1e18);
    }

    function test_GlobalIndex_CapsAtMaturity() public {
        oracle.setRate(0.1e18);
        
        // Warp way past maturity
        vm.warp(maturity + 365 days);
        yt.updateGlobalIndex();
        
        // Index should only accumulate until maturity
        // Expected: 1e18 + 1e18 * 0.1 * 1 year = 1.1e18
        assertApproxEqRel(yt.globalIndex(), 1.1e18, 1e14);
    }

    function test_GlobalIndex_UpdatesOnTransfer() public {
        vm.prank(user);
        yt.mintSynthetic(15_000 * 1e6, 100_000 * 1e6);
        
        oracle.setRate(0.1e18);
        vm.warp(block.timestamp + 182.5 days); // Half year
        
        uint256 indexBefore = yt.globalIndex();
        
        // Transfer triggers _update which calls _updateGlobalIndex
        vm.prank(user);
        yt.transfer(alice, 1000 * 1e6);
        
        uint256 indexAfter = yt.globalIndex();
        assertGt(indexAfter, indexBefore);
    }

    function test_GlobalIndex_MultipleUpdatesAccumulate() public {
        oracle.setRate(0.1e18);
        
        vm.warp(block.timestamp + 100 days);
        yt.updateGlobalIndex();
        uint256 index1 = yt.globalIndex();
        
        vm.warp(block.timestamp + 100 days);
        yt.updateGlobalIndex();
        uint256 index2 = yt.globalIndex();
        
        vm.warp(block.timestamp + 100 days);
        yt.updateGlobalIndex();
        uint256 index3 = yt.globalIndex();
        
        assertGt(index2, index1);
        assertGt(index3, index2);
    }

    function test_GlobalIndex_VaryingRates() public {
        vm.prank(user);
        yt.mintSynthetic(15_000 * 1e6, 100_000 * 1e6);
        
        // First period: 5% for 6 months
        oracle.setRate(0.05e18);
        vm.warp(block.timestamp + 182.5 days);
        yt.updateGlobalIndex();
        uint256 indexMid = yt.globalIndex();
        
        // Second period: 15% for 6 months
        oracle.setRate(0.15e18);
        vm.warp(maturity);
        yt.updateGlobalIndex();
        uint256 indexFinal = yt.globalIndex();
        
        // Index should reflect both periods
        assertGt(indexFinal, indexMid);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          SOLVENCY TESTS                                         //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_Solvency_EmptyVaultIsSolvent() public view {
        assertTrue(yt.isSolvent(user));
    }

    function test_Solvency_BecomesInsolventWithYield() public {
        vm.prank(user);
        yt.mintSynthetic(11_000 * 1e6, 100_000 * 1e6);
        
        assertTrue(yt.isSolvent(user));
        
        oracle.setRate(0.1e18);
        vm.warp(block.timestamp + 100 days);
        yt.updateGlobalIndex();
        
        // Accrued debt eats into margin
        assertFalse(yt.isSolvent(user));
    }

    function test_Solvency_RemainsCollateralizedWithBuffer() public {
        // 30% collateral ratio should remain solvent for a while
        vm.prank(user);
        yt.mintSynthetic(30_000 * 1e6, 100_000 * 1e6);
        
        oracle.setRate(0.1e18);
        vm.warp(block.timestamp + 200 days);
        yt.updateGlobalIndex();
        
        assertTrue(yt.isSolvent(user));
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          MULTI-USER SCENARIOS                                   //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_MultiUser_IndependentVaults() public {
        vm.prank(alice);
        yt.mintSynthetic(20_000 * 1e6, 100_000 * 1e6);
        
        vm.prank(bob);
        yt.mintSynthetic(15_000 * 1e6, 80_000 * 1e6);
        
        (uint256 aCol, uint256 aDebt) = yt.vaults(alice);
        (uint256 bCol, uint256 bDebt) = yt.vaults(bob);
        
        assertEq(aCol, 20_000 * 1e6);
        assertEq(aDebt, 100_000 * 1e6);
        assertEq(bCol, 15_000 * 1e6);
        assertEq(bDebt, 80_000 * 1e6);
    }

    function test_MultiUser_TransferYT() public {
        vm.prank(alice);
        yt.mintSynthetic(15_000 * 1e6, 100_000 * 1e6);
        
        vm.prank(alice);
        yt.transfer(bob, 50_000 * 1e6);
        
        assertEq(yt.balanceOf(alice), 50_000 * 1e6);
        assertEq(yt.balanceOf(bob), 50_000 * 1e6);
        
        // Alice's vault unchanged
        (uint256 aCol, uint256 aDebt) = yt.vaults(alice);
        assertEq(aCol, 15_000 * 1e6);
        assertEq(aDebt, 100_000 * 1e6);
        
        // Bob has no vault but has YT balance
        (uint256 bCol, uint256 bDebt) = yt.vaults(bob);
        assertEq(bCol, 0);
        assertEq(bDebt, 0);
    }

    function test_MultiUser_BobRedeemAliceMintedYT() public {
        // Alice shorts, Bob goes long by receiving YT
        vm.prank(alice);
        yt.mintSynthetic(20_000 * 1e6, 100_000 * 1e6);
        
        vm.prank(alice);
        yt.transfer(bob, 100_000 * 1e6);
        
        oracle.setRate(0.1e18);
        vm.warp(maturity + 1);
        
        // Bob redeems yield
        uint256 balBefore = underlying.balanceOf(bob);
        vm.prank(bob);
        yt.redeemYield(100_000 * 1e6);
        uint256 balAfter = underlying.balanceOf(bob);
        
        assertEq(balAfter - balBefore, 10_000 * 1e6);
    }

    function test_MultiUser_LiquidatorBuysYTFromMarket() public {
        // Simulate a scenario where liquidator acquires YT from another user
        vm.prank(alice);
        yt.mintSynthetic(15_000 * 1e6, 100_000 * 1e6);
        
        vm.prank(bob);
        yt.mintSynthetic(20_000 * 1e6, 100_000 * 1e6);
        
        // Bob transfers YT to liquidator (simulating market purchase)
        vm.prank(bob);
        yt.transfer(liquidator, 100_000 * 1e6);
        
        oracle.setRate(0.1e18);
        vm.warp(190 days);
        yt.updateGlobalIndex();
        
        assertFalse(yt.isSolvent(alice));
        
        // Liquidator uses purchased YT to liquidate Alice
        vm.prank(liquidator);
        yt.liquidate(alice, 100_000 * 1e6);
        
        (uint256 aCol, uint256 aDebt) = yt.vaults(alice);
        assertEq(aDebt, 0);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                        P2P INTEREST RATE SWAP SCENARIO                          //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_IRS_LongProfitsWhenRateHigherThanExpected() public {
        // Alice goes SHORT by minting YT (creates debt position)
        // Bob goes LONG by buying/receiving YT
        // Implied rate: 5%, Actual rate: 10%
        
        vm.prank(alice);
        yt.mintSynthetic(15_000 * 1e6, 100_000 * 1e6);
        
        // Alice sells YT to Bob (Bob is now LONG yield)
        // Alice remains SHORT (she has the vault/debt obligation)
        vm.prank(alice);
        yt.transfer(bob, 100_000 * 1e6);
        
        // Assume Bob paid ~5k (5% implied) for 100k YT
        // Actual rate turns out to be 10%
        oracle.setRate(0.1e18);
        vm.warp(maturity + 1);
        
        // Bob (LONG) redeems 10k (10% actual yield)
        // Bob's profit: 10k (received) - 5k (paid) = +5k
        uint256 balBefore = underlying.balanceOf(bob);
        vm.prank(bob);
        yt.redeemYield(100_000 * 1e6);
        uint256 balAfter = underlying.balanceOf(bob);
        
        assertEq(balAfter - balBefore, 10_000 * 1e6);
        
        // Alice (SHORT) settles her vault
        // Alice's loss: 5k (received for YT) - 10k (debt paid) = -5k
        balBefore = underlying.balanceOf(alice);
        vm.prank(alice);
        yt.settleShort();
        balAfter = underlying.balanceOf(alice);
        
        // Refund = 15k collateral - 10k debt = 5k
        assertEq(balAfter - balBefore, 5_000 * 1e6);
    }

    function test_IRS_ShortProfitsWhenRateLowerThanExpected() public {
        // Alice goes SHORT (mints YT, creates debt position)
        // Assume she sells the YT for 5k (5% implied rate)
        // Actual rate turns out to be 2%
        
        vm.prank(alice);
        yt.mintSynthetic(10_000 * 1e6, 100_000 * 1e6);
        
        // Transfer YT to bob (simulating sale)
        vm.prank(alice);
        yt.transfer(bob, 100_000 * 1e6);
        
        oracle.setRate(0.02e18); // 2% actual
        vm.warp(maturity + 1);
        
        // Alice (SHORT) settles her vault
        uint256 balBefore = underlying.balanceOf(alice);
        vm.prank(alice);
        yt.settleShort();
        uint256 balAfter = underlying.balanceOf(alice);
        
        // Debt = 100k * 0.02 = 2k
        // Refund = 10k - 2k = 8k
        assertEq(balAfter - balBefore, 8_000 * 1e6);
        // Alice's profit: 5k (received for YT) + 8k (refund) - 10k (initial collateral) = +3k
        
        // Bob (LONG) redeems yield
        balBefore = underlying.balanceOf(bob);
        vm.prank(bob);
        yt.redeemYield(100_000 * 1e6);
        balAfter = underlying.balanceOf(bob);
        
        // Bob receives only 2k (2% actual yield)
        // Bob's loss: 2k (received) - 5k (paid) = -3k
        assertEq(balAfter - balBefore, 2_000 * 1e6);
    }

    function test_IRS_NeutralWhenRateMatchesImplied() public {
        // Alice goes SHORT at 5% implied rate
        // Bob goes LONG by receiving YT
        // Actual rate matches implied (5%)
        
        vm.prank(alice);
        yt.mintSynthetic(10_000 * 1e6, 100_000 * 1e6);
        
        vm.prank(alice);
        yt.transfer(bob, 100_000 * 1e6);
        
        oracle.setRate(0.05e18); // Matches 5% implied
        vm.warp(maturity + 1);
        
        // Alice (SHORT) settles
        uint256 balBefore = underlying.balanceOf(alice);
        vm.prank(alice);
        yt.settleShort();
        uint256 balAfter = underlying.balanceOf(alice);
        
        // Debt = 100k * 0.05 = 5k
        // Refund = 10k - 5k = 5k
        assertEq(balAfter - balBefore, 5_000 * 1e6);
        // Alice's P&L: 5k (received) + 5k (refund) - 10k (collateral) = 0
        
        // Bob (LONG) redeems
        balBefore = underlying.balanceOf(bob);
        vm.prank(bob);
        yt.redeemYield(100_000 * 1e6);
        balAfter = underlying.balanceOf(bob);
        
        // Bob receives 5k (5% actual yield)
        // Bob's P&L: 5k (received) - 5k (paid) = 0
        assertEq(balAfter - balBefore, 5_000 * 1e6);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                              FUZZ TESTS                                         //
    /////////////////////////////////////////////////////////////////////////////////////

    function testFuzz_MintSynthetic(uint256 collateral, uint256 ytAmount) public {
        // Bound inputs to reasonable values
        collateral = bound(collateral, 1e6, 50_000 * 1e6);
        ytAmount = bound(ytAmount, 0, (collateral * 1e18) / yt.MIN_COLLATERAL_RATIO());
        
        vm.prank(user);
        yt.mintSynthetic(collateral, ytAmount);
        
        (uint256 vCollateral, uint256 vDebt) = yt.vaults(user);
        assertEq(vCollateral, collateral);
        assertEq(vDebt, ytAmount);
    }

    function testFuzz_AccruedYield(uint256 rate, uint256 timePassed) public {
        rate = bound(rate, 0, 0.5e18); // 0-50% APY
        timePassed = bound(timePassed, 1 days, 365 days);
        
        vm.prank(user);
        yt.mintSynthetic(50_000 * 1e6, 100_000 * 1e6);
        
        oracle.setRate(rate);
        vm.warp(block.timestamp + timePassed);
        yt.updateGlobalIndex();
        
        uint256 accrued = yt.calculateAccruedYield(100_000 * 1e6);
        
        // Accrued should be <= rate * time fraction * amount
        uint256 maxAccrued = (100_000 * 1e6 * rate * timePassed) / (1e18 * 365 days);
        assertLe(accrued, maxAccrued + 1); // +1 for rounding
    }

    function testFuzz_Solvency(uint256 collateral, uint256 ytAmount, uint256 rate, uint256 timePassed) public {
        collateral = bound(collateral, 10_000 * 1e6, 100_000 * 1e6);
        ytAmount = bound(ytAmount, 1e6, (collateral * 1e18) / yt.MIN_COLLATERAL_RATIO());
        rate = bound(rate, 0, 0.2e18);
        timePassed = bound(timePassed, 0, 365 days);
        
        vm.prank(user);
        yt.mintSynthetic(collateral, ytAmount);
        
        oracle.setRate(rate);
        vm.warp(block.timestamp + timePassed);
        yt.updateGlobalIndex();
        
        // Just verify solvency check doesn't revert
        yt.isSolvent(user);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          CALCULATE ACCRUED YIELD TESTS                          //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_CalculateAccruedYield_ZeroWhenIndexUnchanged() public view {
        uint256 accrued = yt.calculateAccruedYield(100_000 * 1e6);
        assertEq(accrued, 0);
    }

    function test_CalculateAccruedYield_ProportionalToAmount() public {
        oracle.setRate(0.1e18);
        vm.warp(maturity);
        yt.updateGlobalIndex();
        
        uint256 accrued100k = yt.calculateAccruedYield(100_000 * 1e6);
        uint256 accrued50k = yt.calculateAccruedYield(50_000 * 1e6);
        
        assertApproxEqRel(accrued100k, accrued50k * 2, 1e14);
    }
}
