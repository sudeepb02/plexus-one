// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";

// V4 Core imports
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

// V4 Test utils
import {Deployers} from "lib/v4-periphery/lib/v4-core/test/utils/Deployers.sol";

// Project imports
import {PlexusYieldHook} from "../src/PlexusYieldHook.sol";
import {YieldToken} from "../src/YieldToken.sol";
import {MockYieldOracle} from "../src/mocks/MockYieldOracle.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract PlexusYieldHookTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    // Core contracts
    PlexusYieldHook public hook;

    // Tokens
    MockERC20 public underlying;
    YieldToken public yieldToken;
    MockYieldOracle public oracle;

    // Pool
    PoolKey public poolKey;
    PoolId public poolId;

    // Test users
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public lp1 = address(0x3);
    address public lp2 = address(0x4);

    // Constants
    uint256 public maturity;
    uint256 public constant INITIAL_UNDERLYING_SUPPLY = 1_000_000 * 1e6; // 1M USDC
    // For 5% APY: Implied Rate = R_und / R_yield = 0.05
    // So with 100k YT, we need 5k underlying (5,000 / 100,000 = 0.05)
    uint256 public constant INITIAL_LIQUIDITY_UNDERLYING = 5_000 * 1e6; // 5k USDC
    uint256 public constant INITIAL_LIQUIDITY_YT = 100_000 * 1e6; // 100k YT

    function setUp() public {
        maturity = block.timestamp + 365 days;

        // Step 1: Deploy PoolManager and Router contracts
        deployFreshManagerAndRouters();

        // Step 2: Deploy underlying token and oracle
        underlying = new MockERC20("Mock USDC", "mockUSDC", 6);
        oracle = new MockYieldOracle();
        oracle.setRate(0.05e18); // 5% APY

        // Step 3: Deploy YieldToken
        yieldToken = new YieldToken("USDC Yield Token", "ytUSDC", address(underlying), maturity);
        yieldToken.setOracle(address(oracle));

        // Step 4: Deploy the hook to an address with the proper flags set
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );

        deployCodeTo(
            "PlexusYieldHook.sol",
            abi.encode(address(manager)),
            address(flags)
        );
        hook = PlexusYieldHook(payable(address(flags)));

        // Step 5: Sort currencies (token0 < token1 by address)
        (Currency currency0, Currency currency1) = _sortCurrencies(address(underlying), address(yieldToken));

        // Step 6: Create pool key with fixed fee of 0.05% (500 in Uniswap V4 fee units)
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 500, // 0.05% fixed fee
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        poolId = poolKey.toId();

        // Step 7: Mint tokens to test users
        _mintTokensToUsers();

        // Step 8: Setup approvals
        _setupApprovals();
    }

    function _sortCurrencies(address tokenA, address tokenB) internal pure returns (Currency, Currency) {
        if (tokenA < tokenB) {
            return (Currency.wrap(tokenA), Currency.wrap(tokenB));
        } else {
            return (Currency.wrap(tokenB), Currency.wrap(tokenA));
        }
    }

    function _mintTokensToUsers() internal {
        // Mint underlying to users
        underlying.mint(address(this), INITIAL_UNDERLYING_SUPPLY);
        underlying.mint(alice, INITIAL_UNDERLYING_SUPPLY);
        underlying.mint(bob, INITIAL_UNDERLYING_SUPPLY);
        underlying.mint(lp1, INITIAL_UNDERLYING_SUPPLY);
        underlying.mint(lp2, INITIAL_UNDERLYING_SUPPLY);

        // Users mint YieldTokens by creating short positions
        // Owner mints YT for initial liquidity
        underlying.approve(address(yieldToken), type(uint256).max);
        yieldToken.mintSynthetic(200_000 * 1e6, 200_000 * 1e6);

        vm.startPrank(alice);
        underlying.approve(address(yieldToken), type(uint256).max);
        yieldToken.mintSynthetic(100_000 * 1e6, 100_000 * 1e6);
        vm.stopPrank();

        vm.startPrank(bob);
        underlying.approve(address(yieldToken), type(uint256).max);
        yieldToken.mintSynthetic(100_000 * 1e6, 100_000 * 1e6);
        vm.stopPrank();

        vm.startPrank(lp1);
        underlying.approve(address(yieldToken), type(uint256).max);
        yieldToken.mintSynthetic(100_000 * 1e6, 100_000 * 1e6);
        vm.stopPrank();

        vm.startPrank(lp2);
        underlying.approve(address(yieldToken), type(uint256).max);
        yieldToken.mintSynthetic(100_000 * 1e6, 100_000 * 1e6);
        vm.stopPrank();
    }

    function _setupApprovals() internal {
        // Owner approvals
        underlying.approve(address(hook), type(uint256).max);
        underlying.approve(address(swapRouter), type(uint256).max);
        underlying.approve(address(manager), type(uint256).max);
        underlying.approve(address(modifyLiquidityRouter), type(uint256).max);
        yieldToken.approve(address(hook), type(uint256).max);
        yieldToken.approve(address(swapRouter), type(uint256).max);
        yieldToken.approve(address(manager), type(uint256).max);
        yieldToken.approve(address(modifyLiquidityRouter), type(uint256).max);

        // Alice approvals
        vm.startPrank(alice);
        underlying.approve(address(hook), type(uint256).max);
        underlying.approve(address(swapRouter), type(uint256).max);
        underlying.approve(address(manager), type(uint256).max);
        yieldToken.approve(address(hook), type(uint256).max);
        yieldToken.approve(address(swapRouter), type(uint256).max);
        yieldToken.approve(address(manager), type(uint256).max);
        vm.stopPrank();

        // Bob approvals
        vm.startPrank(bob);
        underlying.approve(address(hook), type(uint256).max);
        underlying.approve(address(swapRouter), type(uint256).max);
        underlying.approve(address(manager), type(uint256).max);
        yieldToken.approve(address(hook), type(uint256).max);
        yieldToken.approve(address(swapRouter), type(uint256).max);
        yieldToken.approve(address(manager), type(uint256).max);
        vm.stopPrank();

        // LP1 approvals
        vm.startPrank(lp1);
        underlying.approve(address(hook), type(uint256).max);
        underlying.approve(address(swapRouter), type(uint256).max);
        yieldToken.approve(address(hook), type(uint256).max);
        yieldToken.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();

        // LP2 approvals
        vm.startPrank(lp2);
        underlying.approve(address(hook), type(uint256).max);
        underlying.approve(address(swapRouter), type(uint256).max);
        yieldToken.approve(address(hook), type(uint256).max);
        yieldToken.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
    }

    /// @notice Helper to fully initialize the pool with liquidity
    function _initializePoolWithLiquidity() internal {
        // 1. Register the pool
        hook.registerPool(poolKey, address(yieldToken));

        // 2. Initialize the pool in PoolManager with 1:1 price.
        // As we use our custom curve for the price inside the hook, this price is just a placeholder
        // and is completely bypassed by the hook.
        manager.initialize(poolKey, SQRT_PRICE_1_1);

        // 3. Seed initial liquidity via hook (owner only)
        hook.initializeLiquidity(poolKey, INITIAL_LIQUIDITY_UNDERLYING, INITIAL_LIQUIDITY_YT);
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
}
