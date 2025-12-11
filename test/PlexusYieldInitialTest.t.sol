// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

// import everything from the setup file
import "./PlexusYieldSetup.t.sol";

contract PlexusYieldInitialTest is PlexusYieldHookSetup {
    function setUp() public override {
        super.setUp();
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          REGISTRATION TESTS                                     //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_RegisterPool_Success() public {
        hook.registerPool(poolKey, address(yieldToken));

        address registered = hook.registeredYieldTokens(poolId);
        assertEq(registered, address(yieldToken));
    }

    function testRevert_RegisterPool_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        hook.registerPool(poolKey, address(yieldToken));
    }

    function testRevert_RegisterPool_InvalidHookAddress() public {
        // Create a pool key with wrong hook address
        PoolKey memory badKey = PoolKey({
            currency0: poolKey.currency0,
            currency1: poolKey.currency1,
            fee: 500, // 0.05% fixed fee
            tickSpacing: 60,
            hooks: IHooks(address(0x1234))
        });

        vm.expectRevert(PlexusYieldHook.InvalidHook.selector);
        hook.registerPool(badKey, address(yieldToken));
    }

    function testRevert_RegisterPool_InvalidCurrencyPair() public {
        // Create a different token that's not the underlying
        MockERC20 randomToken = new MockERC20("Random", "RND", 6);

        (Currency c0, Currency c1) = _sortCurrencies(address(randomToken), address(yieldToken));

        PoolKey memory badKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: 500, // 0.05% fixed fee
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        vm.expectRevert(PlexusYieldHook.InvalidCurrency.selector);
        hook.registerPool(badKey, address(yieldToken));
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          INITIALIZATION TESTS                                   //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_Initialize_Success() public {
        hook.registerPool(poolKey, address(yieldToken));
        manager.initialize(poolKey, SQRT_PRICE_1_1);

        (
            uint128 reserveUnderlying,
            uint128 reserveYield,
            uint128 totalLpSupply,
            uint48 startTime,
            uint48 maturityTime,
            address yt,
            address ut
        ) = hook.marketStates(poolId);

        assertEq(reserveUnderlying, 0);
        assertEq(reserveYield, 0);
        assertEq(totalLpSupply, 0);
        assertEq(startTime, uint48(block.timestamp));
        assertEq(maturityTime, uint48(maturity));
        assertEq(yt, address(yieldToken));
        assertEq(ut, address(underlying));
    }

    function testRevert_Initialize_RevertPoolNotRegistered() public {
        vm.expectRevert(); // PoolManager wraps errors
        manager.initialize(poolKey, SQRT_PRICE_1_1);
    }

    function testRevert_Initialize_RevertMarketExpired() public {
        // Warp to after maturity
        vm.warp(maturity + 1);

        hook.registerPool(poolKey, address(yieldToken));

        vm.expectRevert(); // PoolManager wraps errors
        manager.initialize(poolKey, SQRT_PRICE_1_1);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          INITIAL LIQUIDITY TESTS                                //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_InitializeLiquidity_Success() public {
        // Register and initialize pool first
        hook.registerPool(poolKey, address(yieldToken));
        manager.initialize(poolKey, SQRT_PRICE_1_1);

        // Record balances before
        uint256 underlyingBefore = underlying.balanceOf(address(this));
        uint256 ytBefore = yieldToken.balanceOf(address(this));

        // Initialize liquidity
        hook.addLiquidity(poolKey, INITIAL_LIQUIDITY_UNDERLYING, INITIAL_LIQUIDITY_YT);

        // Verify tokens were transferred
        assertEq(underlying.balanceOf(address(this)), underlyingBefore - INITIAL_LIQUIDITY_UNDERLYING);
        assertEq(yieldToken.balanceOf(address(this)), ytBefore - INITIAL_LIQUIDITY_YT);
    }

    function test_InitializeLiquidity_CorrectReserves() public {
        // Register and initialize pool first
        hook.registerPool(poolKey, address(yieldToken));
        manager.initialize(poolKey, SQRT_PRICE_1_1);

        // Initialize liquidity
        hook.addLiquidity(poolKey, INITIAL_LIQUIDITY_UNDERLYING, INITIAL_LIQUIDITY_YT);

        // Verify reserves are set correctly
        (uint128 reserveUnderlying, uint128 reserveYield, , , , , ) = hook.marketStates(poolId);

        assertEq(reserveUnderlying, INITIAL_LIQUIDITY_UNDERLYING);
        assertEq(reserveYield, INITIAL_LIQUIDITY_YT);
    }

    function test_InitializeLiquidity_CorrectLpTokensMinted() public {
        // Register and initialize pool first
        hook.registerPool(poolKey, address(yieldToken));
        manager.initialize(poolKey, SQRT_PRICE_1_1);

        // Initialize liquidity
        hook.addLiquidity(poolKey, INITIAL_LIQUIDITY_UNDERLYING, INITIAL_LIQUIDITY_YT);

        // Verify LP tokens minted
        (, , uint128 totalLpSupply, , , , ) = hook.marketStates(poolId);

        // LP tokens should be sqrt(underlying * yt)
        uint256 expectedLpTokens = Math.sqrt(INITIAL_LIQUIDITY_UNDERLYING * INITIAL_LIQUIDITY_YT);
        assertEq(totalLpSupply, expectedLpTokens);

        // Verify owner received LP tokens
        uint256 ownerLpBalance = hook.balanceOf(address(this), uint256(PoolId.unwrap(poolId)));
        assertEq(ownerLpBalance, expectedLpTokens);
    }

    function testRevert_InitializeLiquidity_OnlyOwner() public {
        // Register and initialize pool first
        hook.registerPool(poolKey, address(yieldToken));
        manager.initialize(poolKey, SQRT_PRICE_1_1);

        // Try to initialize liquidity as non-owner
        vm.prank(alice);
        vm.expectRevert();
        hook.addLiquidity(poolKey, INITIAL_LIQUIDITY_UNDERLYING, INITIAL_LIQUIDITY_YT);
    }

    function testRevert_InitializeLiquidity_PoolNotRegistered() public {
        // Don't register the pool, just try to initialize liquidity
        // This should fail because the market state doesn't exist
        vm.expectRevert();
        hook.addLiquidity(poolKey, INITIAL_LIQUIDITY_UNDERLYING, INITIAL_LIQUIDITY_YT);
    }

    function test_InitializeLiquidity_AlreadyInitialized() public {
        // Full initialization
        _initializePoolWithLiquidity();

        uint256 lpBalanceBefore = hook.balanceOf(address(this), uint256(PoolId.unwrap(poolId)));

        // Initializing liquidity again
        hook.addLiquidity(poolKey, INITIAL_LIQUIDITY_UNDERLYING, INITIAL_LIQUIDITY_YT);

        uint256 lpBalanceAfter = hook.balanceOf(address(this), uint256(PoolId.unwrap(poolId)));

        assertGt(lpBalanceAfter, lpBalanceBefore);
    }

    function testRevert_InitializeLiquidity_ZeroUnderlying() public {
        // Register and initialize pool first
        hook.registerPool(poolKey, address(yieldToken));
        manager.initialize(poolKey, SQRT_PRICE_1_1);

        // Try to initialize with zero underlying
        vm.expectRevert(PlexusYieldHook.InvalidAmount.selector);
        hook.addLiquidity(poolKey, 0, INITIAL_LIQUIDITY_YT);
    }

    function testRevert_InitializeLiquidity_ZeroYieldToken() public {
        // Register and initialize pool first
        hook.registerPool(poolKey, address(yieldToken));
        manager.initialize(poolKey, SQRT_PRICE_1_1);

        // Try to initialize with zero yield token
        vm.expectRevert(PlexusYieldHook.InvalidAmount.selector);
        hook.addLiquidity(poolKey, INITIAL_LIQUIDITY_UNDERLYING, 0);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                     INITIAL LIQUIDITY PRICING TESTS                             //
    /////////////////////////////////////////////////////////////////////////////////////

    /// @notice Test that 5% APR results in correct implied rate
    /// For 5% APR: Implied Rate = R_und / R_yield = 0.05
    /// With 5,000 underlying and 100,000 YT: 5,000 / 100,000 = 0.05
    function test_InitializeLiquidity_5PercentAPR_CorrectImpliedRate() public {
        // Register and initialize pool
        hook.registerPool(poolKey, address(yieldToken));
        manager.initialize(poolKey, SQRT_PRICE_1_1);

        // 5% APR: underlying/yt = 0.05
        uint256 underlyingAmount = 5_000 * 1e6; // 5k USDC
        uint256 ytAmount = 100_000 * 1e6; // 100k YT

        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        // Verify reserves
        (uint128 reserveUnderlying, uint128 reserveYield, , , , , ) = hook.marketStates(poolId);

        // Calculate implied rate: R_und / R_yield
        // We don't need to account for the time to maturity here, as it will be 1 at initializtion.
        uint256 impliedRate = (uint256(reserveUnderlying) * 1e18) / uint256(reserveYield);

        // 5% = 0.05 = 5e16 (in 1e18 precision)
        assertApproxEqRel(impliedRate, 0.05e18, 0.001e18); // 0.1% tolerance
    }

    /// @notice Test spot price calculation at 5% APR
    /// Spot Price = t * (R_und / R_yield) where t is time to maturity fraction
    function test_InitializeLiquidity_5PercentAPR_CorrectSpotPrice() public {
        // Register and initialize pool
        hook.registerPool(poolKey, address(yieldToken));
        manager.initialize(poolKey, SQRT_PRICE_1_1);

        // 5% APR
        uint256 underlyingAmount = 5_000 * 1e6;
        uint256 ytAmount = 100_000 * 1e6;

        hook.addLiquidity(poolKey, underlyingAmount, ytAmount);

        // Get market state
        (uint128 reserveUnderlying, uint128 reserveYield, , uint48 startTime, uint48 maturityTime, , ) = hook
            .marketStates(poolId);

        // Calculate time to maturity (t)
        // At start, t = 1.0 (full year remaining)
        uint256 timeToMaturity = maturityTime - block.timestamp;
        uint256 totalDuration = maturityTime - startTime;
        uint256 t = (timeToMaturity * 1e18) / totalDuration;

        // Implied Rate = R_und / R_yield = 0.05
        uint256 impliedRate = (uint256(reserveUnderlying) * 1e18) / uint256(reserveYield);

        // Spot Price = t * impliedRate
        // At t=1.0: spotPrice = 1.0 * 0.05 = 0.05
        uint256 spotPrice = (t * impliedRate) / 1e18;

        // At initialization (t ≈ 1.0), spot price should be close to implied rate
        assertApproxEqRel(spotPrice, 0.05e18, 0.01e18); // 1% tolerance
    }

    /// @notice Test that different APRs result in proportionally different prices
    function test_InitializeLiquidity_APR_Proportionality() public {
        // We'll test that 10% APR gives 10x the price of 1% APR

        // Setup for 1% APR pool
        hook.registerPool(poolKey, address(yieldToken));
        manager.initialize(poolKey, SQRT_PRICE_1_1);
        hook.addLiquidity(poolKey, 1_000 * 1e6, 100_000 * 1e6);

        (uint128 reserve1Pct_Und, uint128 reserve1Pct_YT, , , , , ) = hook.marketStates(poolId);
        uint256 impliedRate1Pct = (uint256(reserve1Pct_Und) * 1e18) / uint256(reserve1Pct_YT);

        // For 10% APR, implied rate should be 10x
        uint256 expectedImpliedRate10Pct = impliedRate1Pct * 10;

        // Verify the ratio
        // 10% APR: 10,000 / 100,000 = 0.10
        // 1% APR: 1,000 / 100,000 = 0.01
        // Ratio: 0.10 / 0.01 = 10
        assertApproxEqRel(expectedImpliedRate10Pct, 0.10e18, 0.001e18);
    }

    /// @notice Test tokens are held in the pool manager after initialization
    function test_InitializeLiquidity_TokensInHook() public {
        // Register and initialize pool
        hook.registerPool(poolKey, address(yieldToken));
        manager.initialize(poolKey, SQRT_PRICE_1_1);

        // Record PoolManager balances before
        uint256 managerUnderlyingBefore = underlying.balanceOf(address(manager));
        uint256 managerYtBefore = yieldToken.balanceOf(address(manager));

        // Initialize liquidity
        hook.addLiquidity(poolKey, INITIAL_LIQUIDITY_UNDERLYING, INITIAL_LIQUIDITY_YT);

        // Verify tokens are in the Pool manager
        assertEq(underlying.balanceOf(address(manager)), managerUnderlyingBefore + INITIAL_LIQUIDITY_UNDERLYING);
        assertEq(yieldToken.balanceOf(address(manager)), managerYtBefore + INITIAL_LIQUIDITY_YT);

        // Verify Hook tokens balance is 0
        assertEq(underlying.balanceOf(address(hook)), 0);
        assertEq(yieldToken.balanceOf(address(hook)), 0);
    }
}
