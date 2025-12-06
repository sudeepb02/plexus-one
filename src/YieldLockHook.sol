// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// V4 imports
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {IPoolManager, ModifyLiquidityParams} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC6909} from "v4-core/ERC6909.sol";

import {YieldToken} from "./YieldToken.sol";

contract YieldLockHook is BaseHook, Ownable, ERC6909 {
    using PoolIdLibrary for PoolKey;
    using SafeCast for int256;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;
    using CurrencyLibrary for Currency;

    using SafeERC20 for IERC20;

    error InvalidCurrency();
    error InvalidAmount();
    error MarketExpired();
    error PoolNotRegistered();

    struct MarketState {
        uint256 reserveUnderlying;
        uint256 reserveYield;
        uint256 maturity;
        address yieldToken;
        address underlyingToken;
        uint256 totalLpSupply;
    }

    mapping(PoolId => MarketState) public marketStates;

    // Registry for valid pools
    mapping(PoolId => address) public registeredYieldTokens;

    error MarketNotInitialized();
    error MarketAlreadySeeded();

    constructor(IPoolManager _manager) BaseHook(_manager) Ownable(msg.sender) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: true,
                beforeRemoveLiquidity: true,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                                    V4 HOOKS                                     //
    /////////////////////////////////////////////////////////////////////////////////////

    function _beforeInitialize(address, PoolKey calldata key, uint160) internal override returns (bytes4) {
        PoolId id = key.toId();
        address ytAddress = registeredYieldTokens[id];

        if (ytAddress == address(0)) revert PoolNotRegistered();

        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        address utAddress = (token0 == ytAddress) ? token1 : token0;

        // Validate maturity
        uint256 maturity = YieldToken(ytAddress).MATURITY();
        if (block.timestamp >= maturity) {
            revert MarketExpired();
        }

        // Initialize Market State
        marketStates[id] = MarketState({
            reserveUnderlying: 0,
            reserveYield: 0,
            maturity: maturity,
            yieldToken: ytAddress,
            underlyingToken: utAddress,
            totalLpSupply: 0
        });

        return BaseHook.beforeInitialize.selector;
    }

    function _beforeAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        return BaseHook.beforeAddLiquidity.selector;
    }

    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        return BaseHook.beforeRemoveLiquidity.selector;
    }

    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                        EXTERNAL PUBLIC FUNCTIONS                                //
    /////////////////////////////////////////////////////////////////////////////////////

    // Liquidity is added to the contract in a single token (Underlying) and the hook calculates
    // the amount of YieldToken to mint based on the current reserve ratio.
    // YieldTokens are minted to the Hook contract to maintain reserves
    function addLiquidity(PoolKey calldata key, uint256 amountUnderlying) external returns (uint256 shares) {
        PoolId id = key.toId();
        MarketState storage state = marketStates[id];

        if (state.maturity == 0 || state.totalLpSupply == 0) revert MarketNotInitialized();
        if (block.timestamp >= state.maturity) revert MarketExpired();

        // Calculate required Yield to match current ratio
        uint256 amountYield = (amountUnderlying * state.reserveYield) / state.reserveUnderlying;

        // Calculate Shares (LP tokens)
        shares = (amountUnderlying * state.totalLpSupply) / state.reserveUnderlying;

        IERC20(state.underlyingToken).safeTransferFrom(msg.sender, address(this), amountUnderlying);

        // Mint Yield to Hook (Reserve)
        YieldToken(state.yieldToken).mint(address(this), amountYield);

        // Update state
        state.reserveUnderlying += amountUnderlying;
        state.reserveYield += amountYield;
        state.totalLpSupply += shares;
        _mint(msg.sender, uint256(PoolId.unwrap(id)), shares);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                         EXTERNAL ADMIN FUNCTIONS                                //
    /////////////////////////////////////////////////////////////////////////////////////

    function registerPool(PoolKey calldata key, address yieldToken) external onlyOwner {
        PoolId id = key.toId();

        if (address(key.hooks) != address(this)) revert("Invalid Hook Address");

        address underlying = YieldToken(yieldToken).UNDERLYING_TOKEN();
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        bool isValidPair = (token0 == yieldToken && token1 == underlying) ||
            (token1 == yieldToken && token0 == underlying);

        if (!isValidPair) revert InvalidCurrency();

        registeredYieldTokens[id] = yieldToken;
    }

    // Seed initial liquidity to the market, which is used to determine the initial rate
    function initializeLiquidity(
        PoolKey calldata key,
        uint256 amountUnderlying,
        uint256 amountYield
    ) external onlyOwner {
        PoolId id = key.toId();
        MarketState storage state = marketStates[id];

        if (state.maturity == 0) revert MarketNotInitialized(); // Must be initialized via V4 first
        if (state.totalLpSupply > 0) revert MarketAlreadySeeded();
        if (amountUnderlying == 0 || amountYield == 0) revert InvalidAmount();

        IERC20(state.underlyingToken).safeTransferFrom(msg.sender, address(this), amountUnderlying);

        // Mint YieldToken to the Hook (hook maintains all the reserve amounts and calcualtions)
        YieldToken(state.yieldToken).mint(address(this), amountYield);

        state.reserveUnderlying = amountUnderlying;
        state.reserveYield = amountYield;
        state.totalLpSupply = amountUnderlying; // Initial shares = Underlying amount

        _mint(msg.sender, uint256(PoolId.unwrap(id)), amountUnderlying);
    }
}
