// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "./PlexusYieldSetup.t.sol";

contract PlexusYieldLiquidityTest is PlexusYieldHookSetup {
    function setUp() public override {
        super.setUp();
        // Initialize pool with liquidity for all liquidity tests
        _initializePoolWithLiquidity();
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          HELPER FUNCTIONS                                       //
    /////////////////////////////////////////////////////////////////////////////////////

    /// @notice Calculate the required YT amount for a given underlying amount to maintain the pool ratio
    function _calculateRequiredYt(uint256 underlyingAmount) internal view returns (uint256) {
        (uint128 reserveUnderlying, uint128 reserveYield, , , , , ) = hook.marketStates(poolId);
        return (underlyingAmount * reserveYield) / reserveUnderlying;
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          ADD LIQUIDITY TESTS                                    //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_AddLiquidity_Success() public {
        // Get initial state
        (uint128 reserveUnderlyingBefore, uint128 reserveYieldBefore, uint128 totalLpSupplyBefore, , , , ) = hook
            .marketStates(poolId);

        // Alice adds liquidity
        uint256 underlyingAmount = 1_000 * 1e6; // 1k USDC
        uint256 ytAmount = _calculateRequiredYt(underlyingAmount);

        uint256 aliceUnderlyingBefore = underlying.balanceOf(alice);
        uint256 aliceYtBefore = yieldToken.balanceOf(alice);

        vm.prank(alice);
        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        // Verify Alice's tokens were transferred
        assertLt(underlying.balanceOf(alice), aliceUnderlyingBefore);
        assertLt(yieldToken.balanceOf(alice), aliceYtBefore);

        // Verify reserves increased
        (uint128 reserveUnderlyingAfter, uint128 reserveYieldAfter, uint128 totalLpSupplyAfter, , , , ) = hook
            .marketStates(poolId);

        assertGt(reserveUnderlyingAfter, reserveUnderlyingBefore);
        assertGt(reserveYieldAfter, reserveYieldBefore);
        assertGt(totalLpSupplyAfter, totalLpSupplyBefore);
    }

    function test_AddLiquidity_ProportionalDeposit() public {
        // Get current reserves to calculate expected YT amount
        (uint128 reserveUnderlying, uint128 reserveYield, , , , , ) = hook.marketStates(poolId);

        uint256 underlyingAmount = 1_000 * 1e6; // 1k USDC

        // Calculate expected YT amount (proportional to reserves)
        uint256 expectedYtAmount = (underlyingAmount * reserveYield) / reserveUnderlying;

        uint256 aliceYtBefore = yieldToken.balanceOf(alice);

        vm.prank(alice);
        hook.addLiquidity(poolKey, underlyingAmount, expectedYtAmount);

        uint256 aliceYtAfter = yieldToken.balanceOf(alice);
        uint256 actualYtSpent = aliceYtBefore - aliceYtAfter;

        // Verify proportional deposit
        assertEq(actualYtSpent, expectedYtAmount);
    }

    function test_AddLiquidity_CorrectLpTokensMinted() public {
        // Get current state
        (uint128 reserveUnderlying, uint128 reserveYield, uint128 totalLpSupply, , , , ) = hook.marketStates(poolId);

        uint256 underlyingAmount = 1_000 * 1e6; // 1k USDC
        uint256 ytAmount = (underlyingAmount * reserveYield) / reserveUnderlying;

        // Calculate expected LP tokens (minimum of the two share calculations)
        uint256 shareU = (underlyingAmount * totalLpSupply) / reserveUnderlying;
        uint256 shareY = (ytAmount * totalLpSupply) / reserveYield;
        uint256 expectedLpTokens = shareU < shareY ? shareU : shareY;

        uint256 aliceLpBefore = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));

        vm.prank(alice);
        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        uint256 aliceLpAfter = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));
        uint256 lpTokensMinted = aliceLpAfter - aliceLpBefore;

        assertEq(lpTokensMinted, expectedLpTokens);
    }

    function test_AddLiquidity_MultipleProviders() public {
        uint256 underlyingAmount = 1_000 * 1e6;
        uint256 ytAmount = _calculateRequiredYt(underlyingAmount);

        // Alice adds liquidity
        vm.prank(alice);

        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        uint256 aliceLp = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));

        // Bob adds the same underlying amount
        // As the ratio of the reserves is the same, the amount of YT required should be the same
        vm.prank(bob);
        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        uint256 bobLp = hook.balanceOf(bob, uint256(PoolId.unwrap(poolId)));

        // Both should receive LP tokens
        assertGt(aliceLp, 0);
        assertGt(bobLp, 0);

        // LP1 adds liquidity
        vm.prank(lp1);
        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        // LP2 adds liquidity
        vm.prank(lp2);
        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        uint256 lp1Balance = hook.balanceOf(lp1, uint256(PoolId.unwrap(poolId)));
        uint256 lp2Balance = hook.balanceOf(lp2, uint256(PoolId.unwrap(poolId)));

        assertGt(lp1Balance, 0);
        assertGt(lp2Balance, 0);

        // As the ratio of the reserves is the same, and everyone addded the same amount of underlying and YT
        // the amount of LP tokens received should be the same

        assertEq(aliceLp, bobLp);
        assertEq(bobLp, lp1Balance);
        assertEq(lp1Balance, lp2Balance);

        // Verify total LP supply increased appropriately
        (, , uint128 totalLpSupply, , , , ) = hook.marketStates(poolId);
        uint256 ownerLp = hook.balanceOf(address(this), uint256(PoolId.unwrap(poolId)));

        assertEq(totalLpSupply, ownerLp + aliceLp + bobLp + lp1Balance + lp2Balance);
    }

    function test_AddLiquidity_PreservesImpliedRate() public {
        // Get initial implied rate
        (uint128 reserveUnderlyingBefore, uint128 reserveYieldBefore, , , , , ) = hook.marketStates(poolId);

        uint256 impliedRateBefore = (uint256(reserveUnderlyingBefore) * 1e18) / uint256(reserveYieldBefore);

        // Alice adds liquidity proportionally
        uint256 underlyingAmount = 1_000 * 1e6;
        uint256 ytAmount = _calculateRequiredYt(underlyingAmount);

        vm.prank(alice);
        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        // Get new implied rate
        (uint128 reserveUnderlyingAfter, uint128 reserveYieldAfter, , , , , ) = hook.marketStates(poolId);

        uint256 impliedRateAfter = (uint256(reserveUnderlyingAfter) * 1e18) / uint256(reserveYieldAfter);

        // Implied rate should be preserved (within tolerance)
        assertApproxEqRel(impliedRateAfter, impliedRateBefore, 0.001e18); // 0.1% tolerance
    }

    function testRevert_AddLiquidity_MarketExpired() public {
        // Warp to after maturity
        vm.warp(maturity + 1);

        vm.prank(alice);
        vm.expectRevert(PlexusYieldHook.MarketExpired.selector);
        hook.addLiquidity(poolKey, 1_000 * 1e6, 20_000 * 1e6);
    }

    function testRevert_AddLiquidity_ZeroUnderlyingAmount() public {
        vm.prank(alice);
        vm.expectRevert(PlexusYieldHook.InvalidAmount.selector);
        hook.addLiquidity(poolKey, 0, 20_000 * 1e6);
    }

    function testRevert_AddLiquidity_ZeroYieldAmount() public {
        vm.prank(alice);
        vm.expectRevert(PlexusYieldHook.InvalidAmount.selector);
        hook.addLiquidity(poolKey, 1_000 * 1e6, 0);
    }

    function testRevert_AddLiquidity_InsufficientYieldTokenBalance() public {
        // Create a user with underlying but no YT
        address randomUser = address(0x999);
        uint256 underlyingAmount = 1_000_000 * 1e6;
        underlying.mint(randomUser, underlyingAmount);

        vm.startPrank(randomUser);
        underlying.approve(address(hook), type(uint256).max);
        yieldToken.approve(address(hook), type(uint256).max);

        // This should revert due to insufficient YT balance
        vm.expectRevert();
        hook.addLiquidity(poolKey, underlyingAmount, 20_000 * 1e6);
        vm.stopPrank();
    }

    function testRevert_AddLiquidity_InsufficientUnderlyingBalance() public {
        // Create a user with YT but no underlying
        address randomUser = address(0x999);
        uint256 underlyingAmount = 100_000 * 1e6;

        // First mint some underlying to get YT
        underlying.mint(randomUser, underlyingAmount);
        vm.startPrank(randomUser);

        underlying.approve(address(yieldToken), type(uint256).max);
        yieldToken.mintSynthetic(underlyingAmount, underlyingAmount);

        // Transfer away all underlying
        underlying.transfer(address(1), underlying.balanceOf(randomUser));

        underlying.approve(address(hook), type(uint256).max);
        yieldToken.approve(address(hook), type(uint256).max);

        // This should revert due to insufficient underlying balance
        vm.expectRevert();
        hook.addLiquidity(poolKey, 1_000 * 1e6, 20_000 * 1e6);
        vm.stopPrank();
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          REMOVE LIQUIDITY TESTS                                 //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_RemoveLiquidity_Success() public {
        // First, Alice adds liquidity
        uint256 underlyingAmount = 1_000 * 1e6;
        uint256 ytAmount = _calculateRequiredYt(underlyingAmount);

        vm.prank(alice);
        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        uint256 aliceLpBalance = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));
        uint256 aliceUnderlyingBefore = underlying.balanceOf(alice);
        uint256 aliceYtBefore = yieldToken.balanceOf(alice);

        // Alice removes half her liquidity
        uint256 lpToRemove = aliceLpBalance / 2;

        vm.prank(alice);
        hook.removeLiquidity(poolKey, lpToRemove);

        // Verify LP tokens were burned
        uint256 aliceLpAfter = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));
        assertEq(aliceLpAfter, aliceLpBalance - lpToRemove);

        // Verify Alice received tokens back
        assertGt(underlying.balanceOf(alice), aliceUnderlyingBefore);
        assertGt(yieldToken.balanceOf(alice), aliceYtBefore);
    }

    function test_RemoveLiquidity_PartialWithdraw() public {
        // Alice adds liquidity
        uint256 underlyingAmount = 2_000 * 1e6;
        uint256 ytAmount = _calculateRequiredYt(underlyingAmount);

        vm.prank(alice);
        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        uint256 aliceLpBalance = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));

        // Remove 25%
        uint256 lpToRemove = aliceLpBalance / 4;

        vm.prank(alice);
        hook.removeLiquidity(poolKey, lpToRemove);

        // Verify 75% remains
        uint256 aliceLpAfter = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));
        assertApproxEqRel(aliceLpAfter, (aliceLpBalance * 3) / 4, 0.001e18);
    }

    function test_RemoveLiquidity_FullWithdraw() public {
        // Alice adds liquidity
        uint256 underlyingAmount = 1_000 * 1e6;
        uint256 ytAmount = _calculateRequiredYt(underlyingAmount);

        vm.prank(alice);
        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        uint256 aliceLpBalance = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));

        // Remove all
        vm.prank(alice);
        hook.removeLiquidity(poolKey, aliceLpBalance);

        // Verify all LP tokens are burned
        uint256 aliceLpAfter = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));
        assertEq(aliceLpAfter, 0);
    }

    function test_RemoveLiquidity_CorrectTokensReturned() public {
        // Alice adds liquidity
        uint256 underlyingAmount = 1_000 * 1e6;
        uint256 ytAmount = _calculateRequiredYt(underlyingAmount);

        vm.prank(alice);
        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        uint256 aliceLpBalance = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));

        // Get reserves after adding (before removal)
        (uint128 reserveUnderlyingMid, uint128 reserveYieldMid, uint128 totalLpSupplyMid, , , , ) = hook.marketStates(
            poolId
        );

        uint256 aliceUnderlyingBefore = underlying.balanceOf(alice);
        uint256 aliceYtBefore = yieldToken.balanceOf(alice);

        // Calculate expected amounts based on pro-rata share
        uint256 expectedUnderlying = (uint256(aliceLpBalance) * reserveUnderlyingMid) / totalLpSupplyMid;
        uint256 expectedYt = (uint256(aliceLpBalance) * reserveYieldMid) / totalLpSupplyMid;

        // Alice removes all liquidity
        vm.prank(alice);
        hook.removeLiquidity(poolKey, aliceLpBalance);

        uint256 underlyingReceived = underlying.balanceOf(alice) - aliceUnderlyingBefore;
        uint256 ytReceived = yieldToken.balanceOf(alice) - aliceYtBefore;

        // Verify correct amounts returned (within tolerance for rounding)
        assertApproxEqAbs(underlyingReceived, expectedUnderlying, 1); // 1 wei tolerance
        assertApproxEqAbs(ytReceived, expectedYt, 1);
    }

    function test_RemoveLiquidity_ReservesDecrease() public {
        // Alice adds liquidity
        uint256 underlyingAmount = 1_000 * 1e6;
        uint256 ytAmount = _calculateRequiredYt(underlyingAmount);

        vm.prank(alice);
        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        (uint128 reserveUnderlyingBefore, uint128 reserveYieldBefore, uint128 totalLpSupplyBefore, , , , ) = hook
            .marketStates(poolId);

        uint256 aliceLpBalance = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));

        // Alice removes liquidity
        vm.prank(alice);
        hook.removeLiquidity(poolKey, aliceLpBalance);

        (uint128 reserveUnderlyingAfter, uint128 reserveYieldAfter, uint128 totalLpSupplyAfter, , , , ) = hook
            .marketStates(poolId);

        // Verify reserves decreased
        assertLt(reserveUnderlyingAfter, reserveUnderlyingBefore);
        assertLt(reserveYieldAfter, reserveYieldBefore);
        assertLt(totalLpSupplyAfter, totalLpSupplyBefore);
    }

    function test_RemoveLiquidity_PreservesImpliedRate() public {
        // Alice adds liquidity
        uint256 underlyingAmount = 1_000 * 1e6;
        uint256 ytAmount = _calculateRequiredYt(underlyingAmount);

        vm.prank(alice);
        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        // Get implied rate before removal
        (uint128 reserveUnderlyingBefore, uint128 reserveYieldBefore, , , , , ) = hook.marketStates(poolId);

        uint256 impliedRateBefore = (uint256(reserveUnderlyingBefore) * 1e18) / uint256(reserveYieldBefore);

        uint256 aliceLpBalance = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));

        // Alice removes half her liquidity
        vm.prank(alice);
        hook.removeLiquidity(poolKey, aliceLpBalance / 2);

        // Get implied rate after removal
        (uint128 reserveUnderlyingAfter, uint128 reserveYieldAfter, , , , , ) = hook.marketStates(poolId);

        uint256 impliedRateAfter = (uint256(reserveUnderlyingAfter) * 1e18) / uint256(reserveYieldAfter);

        // Implied rate should be preserved
        assertApproxEqRel(impliedRateAfter, impliedRateBefore, 0.001e18); // 0.1% tolerance
    }

    function testRevert_RemoveLiquidity_InsufficientLpTokens() public {
        // Alice adds liquidity
        uint256 underlyingAmount = 1_000 * 1e6;
        uint256 ytAmount = _calculateRequiredYt(underlyingAmount);

        vm.startPrank(alice);
        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        uint256 aliceLpBalance = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));

        // Try to remove more than balance
        vm.expectRevert(); // Should revert due to insufficient balance
        hook.removeLiquidity(poolKey, aliceLpBalance + 1);
        vm.stopPrank();
    }

    function testRevert_RemoveLiquidity_ZeroLpTokens() public {
        vm.prank(alice);
        vm.expectRevert(PlexusYieldHook.InvalidAmount.selector);
        hook.removeLiquidity(poolKey, 0);
    }

    function testRevert_RemoveLiquidity_NoLpTokens() public {
        // Alice has no LP tokens, try to remove
        uint256 aliceLpBalance = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));
        assertEq(aliceLpBalance, 0);

        vm.prank(alice);
        vm.expectRevert(); // Should revert due to zero balance
        hook.removeLiquidity(poolKey, 100);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                     ADD/REMOVE LIQUIDITY ROUNDTRIP TESTS                        //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_Liquidity_AddThenRemove_NoLoss() public {
        uint256 underlyingAmount = 1_000 * 1e6;
        uint256 ytAmount = _calculateRequiredYt(underlyingAmount);

        uint256 aliceUnderlyingBefore = underlying.balanceOf(alice);
        uint256 aliceYtBefore = yieldToken.balanceOf(alice);

        // Alice adds liquidity
        vm.startPrank(alice);
        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        uint256 aliceLpBalance = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));

        // Alice immediately removes all liquidity
        hook.removeLiquidity(poolKey, aliceLpBalance);
        vm.stopPrank();

        uint256 aliceUnderlyingAfter = underlying.balanceOf(alice);
        uint256 aliceYtAfter = yieldToken.balanceOf(alice);

        // Alice should get back approximately the same amount (small rounding errors possible)
        assertApproxEqRel(aliceUnderlyingAfter, aliceUnderlyingBefore, 0.01e18); // 1% tolerance
        assertApproxEqRel(aliceYtAfter, aliceYtBefore, 0.01e18);
    }

    function test_Liquidity_MultipleAddRemove_Cycles() public {
        uint256 underlyingAmount = 500 * 1e6;

        vm.startPrank(alice);

        // Cycle 1: Add
        uint256 ytAmount = _calculateRequiredYt(underlyingAmount);
        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);
        uint256 lpAfterAdd1 = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));
        assertGt(lpAfterAdd1, 0);

        // Cycle 1: Remove half
        hook.removeLiquidity(poolKey, lpAfterAdd1 / 2);
        uint256 lpAfterRemove1 = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));
        assertApproxEqRel(lpAfterRemove1, lpAfterAdd1 / 2, 0.001e18);

        // Cycle 2: Add more
        ytAmount = _calculateRequiredYt(underlyingAmount);
        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);
        uint256 lpAfterAdd2 = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));
        assertGt(lpAfterAdd2, lpAfterRemove1);

        // Cycle 2: Remove all
        hook.removeLiquidity(poolKey, lpAfterAdd2);
        uint256 lpAfterRemove2 = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));
        assertEq(lpAfterRemove2, 0);

        vm.stopPrank();
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          LP TOKEN ACCOUNTING TESTS                              //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_LpToken_TotalSupplyMatchesSum() public {
        // Multiple users add liquidity
        uint256 underlyingAmount = 1_000 * 1e6;
        uint256 ytAmount = _calculateRequiredYt(underlyingAmount);

        vm.prank(alice);
        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        underlyingAmount = 2_000 * 1e6;
        ytAmount = _calculateRequiredYt(underlyingAmount);
        vm.prank(bob);
        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        underlyingAmount = 500 * 1e6;
        ytAmount = _calculateRequiredYt(underlyingAmount);
        vm.prank(lp1);
        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        // Get all balances
        uint256 ownerLp = hook.balanceOf(address(this), uint256(PoolId.unwrap(poolId)));
        uint256 aliceLp = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));
        uint256 bobLp = hook.balanceOf(bob, uint256(PoolId.unwrap(poolId)));
        uint256 lp1Lp = hook.balanceOf(lp1, uint256(PoolId.unwrap(poolId)));

        // Get total supply from market state
        (, , uint128 totalLpSupply, , , , ) = hook.marketStates(poolId);

        // Total supply should equal sum of all balances
        assertEq(totalLpSupply, ownerLp + aliceLp + bobLp + lp1Lp);
    }

    function test_LpToken_ProRataShare() public {
        // Get initial owner LP balance (from initialization)
        uint256 ownerLp = hook.balanceOf(address(this), uint256(PoolId.unwrap(poolId)));

        // Alice adds the same amount as initial liquidity
        uint256 ytAmount = _calculateRequiredYt(INITIAL_LIQUIDITY_UNDERLYING);

        vm.prank(alice);
        hook.addLiquidity(poolKey, INITIAL_LIQUIDITY_UNDERLYING, ytAmount);

        uint256 aliceLp = hook.balanceOf(alice, uint256(PoolId.unwrap(poolId)));

        // Alice should get approximately the same LP tokens as owner
        assertApproxEqRel(aliceLp, ownerLp, 0.05e18);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                     IMBALANCED LIQUIDITY TESTS                                  //
    /////////////////////////////////////////////////////////////////////////////////////

    /// @notice Test that adding imbalanced liquidity gives LP tokens based on the smaller share
    function test_AddLiquidity_ImbalancedDeposit_UsesMinShare() public {
        (uint128 reserveUnderlying, uint128 reserveYield, uint128 totalLpSupply, , , , ) = hook.marketStates(poolId);

        // Add more underlying than proportionally required
        uint256 underlyingAmount = 1_000 * 1e6;
        uint256 proportionalYt = (underlyingAmount * reserveYield) / reserveUnderlying;
        uint256 excessYt = proportionalYt * 2; // 2x the required YT

        // Calculate expected shares (should be based on underlying, the smaller ratio)
        uint256 shareU = (underlyingAmount * totalLpSupply) / reserveUnderlying;
        uint256 shareY = (excessYt * totalLpSupply) / reserveYield;
        uint256 expectedShares = shareU < shareY ? shareU : shareY; // Should be shareU

        vm.prank(alice);
        uint256 actualShares = hook.addLiquidity(poolKey, underlyingAmount, excessYt);

        assertEq(actualShares, expectedShares);
        assertEq(actualShares, shareU); // Confirms it used the underlying-based share
    }
}
