// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

// V4 imports
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {IPoolManager, ModifyLiquidityParams} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC6909} from "v4-core/ERC6909.sol";

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {LogExpMath} from "./lib/LogExpMath.sol";
import {YieldMath} from "./lib/YieldMath.sol";

import {YieldToken} from "./YieldToken.sol";

contract YieldLockHook is BaseHook, Ownable, ERC6909 {
    using PoolIdLibrary for PoolKey;
    using SafeCast for int256;
    using SafeCast for uint256;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;
    using CurrencyLibrary for Currency;

    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;
    using LogExpMath for uint256;
    using YieldMath for uint256;

    error InvalidCurrency();
    error InvalidAmount();
    error MarketExpired();
    error PoolNotRegistered();
    error MarketNotInitialized();
    error MarketAlreadySeeded();
    error AddLiquidityThroughHook();
    error RemoveLiquidityThroughHook();

    struct MarketState {
        uint128 reserveUnderlying;
        uint128 reserveYield;
        uint128 totalLpSupply;
        uint48 startTime;
        uint48 maturity;
        address yieldToken;
        address underlyingToken;
    }

    mapping(PoolId => MarketState) public marketStates;

    // Registry for valid pools
    mapping(PoolId => address) public registeredYieldTokens;

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
        if (key.currency0.isAddressZero()) revert InvalidCurrency(); // Disallow native tokens

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
            totalLpSupply: 0,
            startTime: uint48(block.timestamp),
            maturity: uint48(maturity),
            yieldToken: ytAddress,
            underlyingToken: utAddress
        });

        return BaseHook.beforeInitialize.selector;
    }

    function _beforeAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override pure returns (bytes4) {
        revert AddLiquidityThroughHook();
    }

    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override pure returns (bytes4) {
        revert RemoveLiquidityThroughHook();
    }

    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        MarketState storage state = marketStates[key.toId()];

        if (block.timestamp >= state.maturity) revert MarketExpired();
        if (state.totalLpSupply == 0) revert MarketNotInitialized();

        bool isExactInput;
        int128 unspecifiedDelta;

        // scoped block to avoid stack too deep error
        {
            // 1. Determine Swap Context from params
            Currency currencyIn;
            Currency currencyOut;
            uint256 amount;

            (currencyIn, currencyOut, amount, isExactInput) = _getSwapContext(key, params);
            bool isInputUnderlying = Currency.unwrap(currencyIn) == state.underlyingToken;

            // 2. Calculate Swap Result
            (uint256 amountIn, uint256 amountOut, uint256 newRUnd, uint256 newRYield) = _calculateSwapResult(
                state,
                isExactInput,
                isInputUnderlying,
                amount
            );

            // 3. Update State with new reserve values
            state.reserveUnderlying = newRUnd.toUint128();
            state.reserveYield = newRYield.toUint128();

            _take(currencyIn, amountIn);
            _settle(currencyOut, amountOut);

            // 4. Construct Delta & Settle
            // We return a delta that cancels out the user's specified amount, effectively skipping the core swap logic.
            // We must also return the correct unspecified delta so the PoolManager knows how much the user receives/pays.

            if (isExactInput) {
                // Exact Input: Unspecified is Output
                // Hook gives Output -> Negative Delta
                unspecifiedDelta = -amountOut.toInt128();
            } else {
                // Exact Output: Unspecified is Input
                // Hook takes Input -> Positive Delta
                unspecifiedDelta = amountIn.toInt128();
            }
        }

        BeforeSwapDelta delta = toBeforeSwapDelta(
            -int128(params.amountSpecified), // Specified: Cancel out the input/output
            unspecifiedDelta // Unspecified: The amount the hook takes/gives
        );

        return (BaseHook.beforeSwap.selector, delta, 0);
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

        // Mint Yield to Hook (Reserve), acts as virtual tokens for accounting
        YieldToken(state.yieldToken).mint(address(this), amountYield);

        // Update state
        state.reserveUnderlying += amountUnderlying.toUint128();
        state.reserveYield += amountYield.toUint128();
        state.totalLpSupply += shares.toUint128();

        // Mint LP tokens (ERC6909)
        _mint(msg.sender, uint256(PoolId.unwrap(id)), shares);
    }

    function removeLiquidity(
        PoolKey calldata key,
        uint256 shares
    ) external returns (uint256 amountUnderlying, uint256 amountYield) {
        PoolId id = key.toId();
        MarketState storage state = marketStates[id];

        if (state.totalLpSupply == 0) revert MarketNotInitialized();
        if (shares == 0) revert InvalidAmount();

        // Calculate amounts for Underlying and YieldToken
        amountUnderlying = (shares * state.reserveUnderlying) / state.totalLpSupply;
        amountYield = (shares * state.reserveYield) / state.totalLpSupply;

        // Burn LP tokens (ERC6909)
        _burn(msg.sender, uint256(PoolId.unwrap(id)), shares);

        // Update state
        state.reserveUnderlying -= amountUnderlying.toUint128();
        state.reserveYield -= amountYield.toUint128();
        state.totalLpSupply -= shares.toUint128();

        // Transfer Underlying to user
        IERC20(state.underlyingToken).safeTransfer(msg.sender, amountUnderlying);

        // Burn YieldTokens from the Hook (virtual tokens removed from circulation)
        YieldToken(state.yieldToken).burn(address(this), amountYield);
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

        state.reserveUnderlying = amountUnderlying.toUint128();
        state.reserveYield = amountYield.toUint128();
        state.totalLpSupply = amountUnderlying.toUint128(); // Initial shares = Underlying amount

        _mint(msg.sender, uint256(PoolId.unwrap(id)), amountUnderlying);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                         INTERNAL HELPER FUNCTIONS                               //
    /////////////////////////////////////////////////////////////////////////////////////

    function _getNormalizedTime(uint48 startTime, uint48 maturity) internal view returns (uint256) {
        // Normalized time is the fractional representation of how much time has passed from the startTime to maturity
        // It's value is 1 at startTime and 0 at maturity
        // Normalized time = (maturity - currentTime) / (maturity - startTime)
        // The value is scaled by 1e18 for precision

        uint256 currentTime = block.timestamp;

        // Return 0 if the maturity has already passed
        if (currentTime >= maturity) return 0;

        return ((uint256(maturity) - currentTime) * 1e18) / (uint256(maturity) - startTime);
    }

    function _getSwapContext(
        PoolKey calldata key,
        SwapParams calldata params
    ) internal pure returns (Currency currencyIn, Currency currencyOut, uint256 amount, bool isExactInput) {
        // amountSpecified < 0 implies Exact Input (User specifies amount to pay, hence negative)
        // amountSpecified > 0 implies Exact Output (User specifies amount to receive, hence positive)
        isExactInput = params.amountSpecified < 0;
        amount = isExactInput ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);

        if (params.zeroForOne) {
            currencyIn = key.currency0;
            currencyOut = key.currency1;
        } else {
            currencyIn = key.currency1;
            currencyOut = key.currency0;
        }
    }

    function _calculateSwapResult(
        MarketState storage state,
        bool isExactInput,
        bool isInputUnderlying,
        uint256 amount
    ) internal view returns (uint256 amountIn, uint256 amountOut, uint256 newRUnd, uint256 newRYield) {
        uint256 t = _getNormalizedTime(state.startTime, state.maturity);

        if (isExactInput) {
            (amountOut, newRUnd, newRYield) = YieldMath.computeOutGivenExactIn(
                state.reserveUnderlying,
                state.reserveYield,
                isInputUnderlying,
                amount,
                t
            );
            amountIn = amount;
        } else {
            // amount is amountOut
            (amountIn, newRUnd, newRYield) = YieldMath.computeInGivenExactOut(
                state.reserveUnderlying,
                state.reserveYield,
                !isInputUnderlying,
                amount,
                t
            );
            amountOut = amount;
        }
    }

    function _settle(Currency currency, uint256 amount) internal {
        poolManager.sync(currency);
        currency.transfer(address(poolManager), amount);
        poolManager.settle();
    }

    function _take(Currency currency, uint256 amount) internal {
        poolManager.take(currency, address(this), amount);
    }
}
