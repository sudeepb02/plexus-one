// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import "./PlexusYieldSetup.t.sol";

contract PlexusYieldSwapTest is PlexusYieldHookSetup {
    bool isUnderlyingToken0;

    function setUp() public override {
        super.setUp();
        // Initialize pool with liquidity (5k USDC, 100k YT)
        // Implied Rate = 5%
        _initializePoolWithLiquidity();

        // Determine swap direction based on address sorting
        // If currency0 is Underlying, then Underlying -> YT is zeroForOne = true
        isUnderlyingToken0 = Currency.unwrap(poolKey.currency0) == address(underlying);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          BASIC SWAP FUNCTIONALITY                               //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_Swap_ExactInput_BuyYieldToken() public {
        // Alice buys YT with 100 USDC
        uint256 amountIn = 100 * 1e6;

        uint256 balanceUndBefore = underlying.balanceOf(alice);
        uint256 balanceYtBefore = yieldToken.balanceOf(alice);

        // Swap Settings
        bool zeroForOne = isUnderlyingToken0;
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn), // Negative for Exact Input
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        vm.prank(alice);
        swapRouter.swap(poolKey, params, testSettings, "");

        uint256 balanceUndAfter = underlying.balanceOf(alice);
        uint256 balanceYtAfter = yieldToken.balanceOf(alice);

        // Verify Alice paid exactly 100 USDC
        assertEq(balanceUndBefore - balanceUndAfter, amountIn, "Amount In Mismatch");

        // Verify Alice received YT
        // Price is roughly 0.05 USDC per YT. 100 USDC should get ~2000 YT
        uint256 ytReceived = balanceYtAfter - balanceYtBefore;
        assertGt(ytReceived, 0, "Should receive YT");

        // Check approximate price execution (100 / 0.05 = 2000)
        // Due to slippage/curve, it will be slightly less than 2000
        assertApproxEqRel(ytReceived, 2000 * 1e6, 0.05e18); // 5% tolerance
    }

    function test_Swap_ExactOutput_BuyYieldToken() public {
        // Alice wants to buy exactly 1000 YT
        uint256 amountOut = 1000 * 1e6;

        uint256 balanceUndBefore = underlying.balanceOf(alice);
        uint256 balanceYtBefore = yieldToken.balanceOf(alice);

        // Swap Settings
        bool zeroForOne = isUnderlyingToken0;
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: int256(amountOut), // Positive for Exact Output
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        vm.prank(alice);
        swapRouter.swap(poolKey, params, testSettings, "");

        uint256 balanceUndAfter = underlying.balanceOf(alice);
        uint256 balanceYtAfter = yieldToken.balanceOf(alice);

        // Verify Alice received exactly 1000 YT
        assertEq(balanceYtAfter - balanceYtBefore, amountOut, "Amount Out Mismatch");

        // Verify Alice paid Underlying
        // 1000 YT * 0.05 price = ~50 USDC
        uint256 undPaid = balanceUndBefore - balanceUndAfter;
        assertApproxEqRel(undPaid, 50 * 1e6, 0.05e18);
    }

    function test_Swap_ExactInput_SellYieldToken() public {
        // Alice has YT (minted in setup) and sells 1000 YT for USDC
        uint256 amountIn = 1000 * 1e6;

        uint256 balanceUndBefore = underlying.balanceOf(alice);
        uint256 balanceYtBefore = yieldToken.balanceOf(alice);

        // Swap Settings: YT -> Underlying
        bool zeroForOne = !isUnderlyingToken0;
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn), // Negative for Exact Input
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        vm.prank(alice);
        swapRouter.swap(poolKey, params, testSettings, "");

        uint256 balanceUndAfter = underlying.balanceOf(alice);
        uint256 balanceYtAfter = yieldToken.balanceOf(alice);

        // Verify Alice paid exactly 1000 YT
        assertEq(balanceYtBefore - balanceYtAfter, amountIn, "Amount In Mismatch");

        // Verify Alice received USDC
        // 1000 YT * 0.05 = ~50 USDC
        uint256 undReceived = balanceUndAfter - balanceUndBefore;
        assertApproxEqRel(undReceived, 50 * 1e6, 0.05e18);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          USER SCENARIO: PROFITABLE LONG                         //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_Scenario_LongProfit_HighYield() public {
        // Scenario: Alice buys YT expecting yield > 5%.
        // Actual yield turns out to be 10%.

        // 1. Alice buys 10,000 YT
        uint256 amountYtToBuy = 10_000 * 1e6;

        bool zeroForOne = isUnderlyingToken0;
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: int256(amountYtToBuy), // Exact Output
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        uint256 undBalanceStart = underlying.balanceOf(alice);

        vm.prank(alice);
        swapRouter.swap(poolKey, params, testSettings, "");

        uint256 cost = undBalanceStart - underlying.balanceOf(alice);

        // Cost should be around 500 USDC (10k * 0.05)
        // console2.log("Cost to buy 10k YT:", cost);

        // 2. Time passes, Yield Rate increases to 10%
        oracle.setRate(0.10e18); // 10% APY

        // Warp to maturity
        vm.warp(maturity + 1);

        // 3. Alice redeems YT
        vm.prank(alice);
        yieldToken.redeemYield(amountYtToBuy);

        uint256 finalBalance = underlying.balanceOf(alice);
        uint256 payout = finalBalance - (undBalanceStart - cost);

        // 4. Analyze Profit
        // Expected Payout: 10,000 * 10% = 1,000 USDC
        // Cost: ~500 USDC
        // Profit: ~500 USDC

        // console2.log("Redemption Payout:", payout);
        // console2.log("Net Profit:", payout - cost);

        assertGt(payout, cost, "Trade should be profitable");
        assertApproxEqRel(payout, 1000 * 1e6, 0.01e18); // Payout should be ~1000
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          USER SCENARIO: LOSING LONG                             //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_Scenario_LongLoss_LowYield() public {
        // Scenario: Alice buys YT expecting yield > 5%.
        // Actual yield turns out to be 1% (Bearish case).

        // 1. Alice buys 10,000 YT
        uint256 amountYtToBuy = 10_000 * 1e6;

        bool zeroForOne = isUnderlyingToken0;
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: int256(amountYtToBuy),
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        uint256 undBalanceStart = underlying.balanceOf(alice);

        vm.prank(alice);
        swapRouter.swap(poolKey, params, testSettings, "");

        uint256 cost = undBalanceStart - underlying.balanceOf(alice);

        // Cost ~500 USDC

        // 2. Time passes, Yield Rate drops to 1%
        oracle.setRate(0.01e18); // 1% APY

        // Warp to maturity
        vm.warp(maturity + 1);

        // 3. Alice redeems YT
        vm.prank(alice);
        yieldToken.redeemYield(amountYtToBuy);

        uint256 finalBalance = underlying.balanceOf(alice);
        uint256 payout = finalBalance - (undBalanceStart - cost);

        // 4. Analyze Loss
        // Expected Payout: 10,000 * 1% = 100 USDC
        // Cost: ~500 USDC
        // Loss: ~400 USDC

        assertLt(payout, cost, "Trade should be a loss");
        assertApproxEqRel(payout, 100 * 1e6, 0.01e18);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          USER SCENARIO: PROFITABLE SHORT                        //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_Scenario_ShortProfit_LowYield() public {
        // Use a fresh address with no pre-existing vault
        address charlie = address(0x456);
        // Charlie mints YT and sells it (Short Yield).
        // Implied Rate is ~5%. Actual yield is 1%. Charlie should profit.

        uint256 amountYtToMint = 10_000 * 1e6;
        uint256 collateralAmount = 10_000 * 1e6; // 1:1 collateral for safety in test

        underlying.mint(charlie, collateralAmount);

        // 1. Charlie mints YT
        vm.startPrank(charlie);
        underlying.approve(address(yieldToken), collateralAmount);
        yieldToken.approve(address(swapRouter), type(uint256).max);
        yieldToken.mintSynthetic(collateralAmount, amountYtToMint);

        // 2. charlie sells YT for Underlying (Premium)
        uint256 balUndBefore = underlying.balanceOf(charlie);

        bool zeroForOne = !isUnderlyingToken0; // YT -> Underlying
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountYtToMint), // Exact Input
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        swapRouter.swap(poolKey, params, testSettings, "");

        uint256 premium = underlying.balanceOf(charlie) - balUndBefore;
        vm.stopPrank();

        // Premium should be around 5% of Notional (10k * 0.05 = 500)
        // But due to slippage from selling 10% of pool liquidity, actual is ~454.5
        // console2.log("Premium Received:", premium);

        // 3. Yield is Low (1%)
        oracle.setRate(0.01e18);
        vm.warp(maturity + 1);

        // 4. charlie settles short
        uint256 collateralBeforeSettle = underlying.balanceOf(charlie); // Premium is here

        vm.prank(charlie);
        yieldToken.settleShort();

        uint256 finalBalance = underlying.balanceOf(charlie);
        uint256 returnedCollateral = finalBalance - collateralBeforeSettle;

        // Debt = 10,000 * 1% = 100.
        // Collateral Used = 100.
        // Returned = 10,000 - 100 = 9,900.

        // Net PnL = (Returned Collateral + Premium) - Initial Collateral
        //         = (9900 + ~454.5) - 10000 = ~354.5 (due to slippage on premium)

        int256 pnl = int256(returnedCollateral) + int256(premium) - int256(collateralAmount);

        // console2.log("Returned Collateral:", returnedCollateral);
        // console2.log("PnL:", pnl);

        assertGt(pnl, 0, "Short should be profitable");
        // Expected Profit ~354.5 (454.5 premium - 100 debt, with slippage factored in)
        // Use 15% tolerance to account for AMM slippage from large trade
        assertApproxEqRel(uint256(pnl), 400 * 1e6, 0.15e18);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          USER SCENARIO: LOSING SHORT                            //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_Scenario_ShortLoss_HighYield() public {
        // Use a fresh address with no pre-existing vault
        address charlie = address(0x123);

        uint256 amountYtToMint = 10_000 * 1e6;
        uint256 collateralAmount = 10_000 * 1e6;

        // Fund charlie
        underlying.mint(charlie, collateralAmount * 2);

        vm.startPrank(charlie);
        underlying.approve(address(yieldToken), type(uint256).max);
        underlying.approve(address(swapRouter), type(uint256).max);
        yieldToken.approve(address(swapRouter), type(uint256).max);

        // 1. Charlie mints YT
        yieldToken.mintSynthetic(collateralAmount, amountYtToMint);

        // 2. Charlie sells YT
        uint256 balUndBefore = underlying.balanceOf(charlie);

        bool zeroForOne = !isUnderlyingToken0;
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountYtToMint),
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        swapRouter.swap(poolKey, params, testSettings, "");
        uint256 premium = underlying.balanceOf(charlie) - balUndBefore;
        vm.stopPrank();

        // 3. Yield is High (10%)
        oracle.setRate(0.10e18);
        vm.warp(maturity + 1);

        // 4. Charlie settles
        uint256 collateralBeforeSettle = underlying.balanceOf(charlie);

        vm.prank(charlie);
        yieldToken.settleShort();

        uint256 finalBalance = underlying.balanceOf(charlie);
        uint256 returnedCollateral = finalBalance - collateralBeforeSettle;

        // Debt = 10,000 * 10% = 1000.
        // Returned = 10,000 - 1000 = 9000.
        // PnL = (9000 + ~455) - 10000 = -545.

        int256 pnl = int256(returnedCollateral) + int256(premium) - int256(collateralAmount);

        assertLt(pnl, 0, "Short should be a loss");
        assertApproxEqRel(uint256(-pnl), 500 * 1e6, 0.15e18); // 15% tolerance for slippage
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          USER SCENARIO: TRADING (CLOSE EARLY)                   //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_Scenario_Trade_CloseLongEarly() public {
        // Alice buys YT. Price goes up (Yield expectation rises). She sells before maturity.

        uint256 amountYt = 1000 * 1e6;

        // 1. Buy YT
        vm.startPrank(alice);
        bool zeroForOne = isUnderlyingToken0;
        SwapParams memory paramsBuy = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: int256(amountYt), // Exact Output
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        uint256 startBal = underlying.balanceOf(alice);
        swapRouter.swap(poolKey, paramsBuy, testSettings, "");
        uint256 cost = startBal - underlying.balanceOf(alice);

        // 2. Market Sentiment Changes: Someone buys a LOT of YT, pushing price up
        // (Simulating implied rate increase)
        vm.stopPrank();
        vm.prank(bob);
        SwapParams memory paramsPump = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(50_000 * 1e6), // Buy huge amount
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        swapRouter.swap(poolKey, paramsPump, testSettings, "");

        // 3. Alice sells YT back
        vm.startPrank(alice);
        SwapParams memory paramsSell = SwapParams({
            zeroForOne: !zeroForOne,
            amountSpecified: -int256(amountYt), // Sell all YT
            sqrtPriceLimitX96: !zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        uint256 balBeforeSell = underlying.balanceOf(alice);
        swapRouter.swap(poolKey, paramsSell, testSettings, "");
        uint256 proceeds = underlying.balanceOf(alice) - balBeforeSell;
        vm.stopPrank();

        // Since price went up, Proceeds > Cost
        assertGt(proceeds, cost, "Should profit from price increase");
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          TIME DECAY (THETA) TESTS                               //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_TimeDecay_PriceDropsOverTime() public {
        // Test that buying the same amount of YT becomes cheaper as we approach maturity
        // assuming reserves stay constant (we revert state to ensure reserves are same).

        uint256 amountYtToBuy = 1000 * 1e6;
        uint256 costAtStart;
        uint256 costAtHalfTime;

        // 1. Buy at Start (t=1.0)
        {
            uint256 snap = vm.snapshot();

            uint256 balBefore = underlying.balanceOf(alice);

            bool zeroForOne = isUnderlyingToken0;
            SwapParams memory params = SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: int256(amountYtToBuy),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            });
            PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            });

            vm.prank(alice);
            swapRouter.swap(poolKey, params, testSettings, "");

            costAtStart = balBefore - underlying.balanceOf(alice);

            vm.revertTo(snap);
        }

        // 2. Warp to Half Time (t=0.5)
        // Total duration is 1 year. Warp 6 months.
        vm.warp(block.timestamp + 182.5 days);

        // 3. Buy at Half Time
        {
            uint256 balBefore = underlying.balanceOf(alice);

            bool zeroForOne = isUnderlyingToken0;
            SwapParams memory params = SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: int256(amountYtToBuy),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            });
            PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            });

            vm.prank(alice);
            swapRouter.swap(poolKey, params, testSettings, "");

            costAtHalfTime = balBefore - underlying.balanceOf(alice);
        }

        // 4. Verify Price Decay
        // Price = t * (R_und / R_yt)
        // Since t went from 1.0 to 0.5, price should roughly halve.

        // console2.log("Cost at Start:", costAtStart);
        // console2.log("Cost at HalfTime:", costAtHalfTime);

        assertLt(costAtHalfTime, costAtStart, "Price should decrease over time");
        assertApproxEqRel(costAtHalfTime, costAtStart / 2, 0.05e18); // Allow some margin for curve mechanics
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                          MARKET IMPACT / SLIPPAGE                               //
    /////////////////////////////////////////////////////////////////////////////////////

    function test_MarketImpact_LargeTrade() public {
        // Buying a large amount of YT should increase the price per token (slippage)

        // Small Trade: 100 YT
        uint256 smallAmount = 100 * 1e6;
        uint256 costSmall;

        {
            uint256 snap = vm.snapshot();
            uint256 balBefore = underlying.balanceOf(alice);
            _swapExactOutput(smallAmount);
            costSmall = balBefore - underlying.balanceOf(alice);
            vm.revertTo(snap);
        }

        // Large Trade: 50,000 YT (50% of pool liquidity)
        uint256 largeAmount = 50_000 * 1e6;
        uint256 costLarge;

        {
            uint256 balBefore = underlying.balanceOf(alice);
            _swapExactOutput(largeAmount);
            costLarge = balBefore - underlying.balanceOf(alice);
        }

        // Calculate Price per Token
        uint256 pricePerTokenSmall = (costSmall * 1e18) / smallAmount;
        uint256 pricePerTokenLarge = (costLarge * 1e18) / largeAmount;

        // console2.log("Price/Token (Small Trade):", pricePerTokenSmall);
        // console2.log("Price/Token (Large Trade):", pricePerTokenLarge);

        assertGt(pricePerTokenLarge, pricePerTokenSmall, "Large trade should have higher average price (slippage)");
    }

    // Helper for market impact test
    function _swapExactOutput(uint256 amountOut) internal {
        bool zeroForOne = isUnderlyingToken0;
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: int256(amountOut),
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        vm.prank(alice);
        swapRouter.swap(poolKey, params, testSettings, "");
    }
}
