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
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {CurrencySettler} from "v4-core-test/utils/CurrencySettler.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC6909} from "v4-core/ERC6909.sol";

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {LogExpMath} from "./lib/LogExpMath.sol";
import {YieldMath} from "./lib/YieldMath.sol";

import {YieldToken} from "./YieldToken.sol";

contract PlexusYieldHook is BaseHook, Ownable, ERC6909, IUnlockCallback {
    using PoolIdLibrary for PoolKey;
    using SafeCast for int256;
    using SafeCast for uint256;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;

    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;
    using LogExpMath for uint256;
    using YieldMath for uint256;

    error InvalidCurrency();
    error InvalidAmount();
    error InvalidHook();
    error InvalidMaturity();
    error MarketExpired();
    error PoolNotRegistered();
    error MarketNotInitialized();
    error MarketAlreadySeeded();
    error AddLiquidityThroughHook();
    error RemoveLiquidityThroughHook();
    error OnlyOwnerCanInitializeLiquidity();

    struct MarketState {
        uint128 reserveUnderlying;
        uint128 reserveYield;
        uint128 totalLpSupply;
        uint48 startTime;
        uint48 maturity;
        address yieldToken;
        address underlyingToken;
    }

    struct PMCallbackData {
        uint8 actionType; // 0 for add liquidity, 1 for remove liquidity
        address sender;
        uint256 amountUnderlying;
        uint256 amountYield;
        uint256 shares;
        PoolKey key;
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
        if (maturity >= type(uint48).max) revert InvalidMaturity();
        if (block.timestamp >= maturity) revert MarketExpired();

        // Initialize Market State
        marketStates[id] = MarketState({
            reserveUnderlying: 0,
            reserveYield: 0,
            totalLpSupply: 0,
            startTime: uint48(block.timestamp),
            // casting maturity to 'uint48' is safe as we're validating the maturity value above
            // forge-lint: disable-next-line(unsafe-typecast)
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
    ) internal pure override returns (bytes4) {
        revert AddLiquidityThroughHook();
    }

    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal pure override returns (bytes4) {
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

            // 4. Settle

            // Take currencyIn amountIn from the user to the PoolManager, and take claim tokens to the hook
            currencyIn.take(poolManager, address(this), amountIn, true);

            // Burn currencyOut amountOut claimTOkens from the hook to the PoolManager, and settle actual tokens to the user
            currencyOut.settle(poolManager, address(this), amountOut, true);

            if (isExactInput) {
                unspecifiedDelta = -amountOut.toInt128();
            } else {
                unspecifiedDelta = amountIn.toInt128();
            }
        }

        // 5. Prepare BeforeSwapDelta
        BeforeSwapDelta delta = toBeforeSwapDelta(-int128(params.amountSpecified), unspecifiedDelta);

        return (BaseHook.beforeSwap.selector, delta, 0);
    }

    // Called by the PoolManager upon unlocking during the addLiquidity/removeLiquidity function calls
    function unlockCallback(bytes calldata data) external override onlyPoolManager returns (bytes memory) {
        PMCallbackData memory callbackData = abi.decode(data, (PMCallbackData));

        if (callbackData.actionType == 0) {
            uint256 shares = _addLiquidityThroughHook(
                callbackData.key,
                callbackData.sender,
                callbackData.amountUnderlying,
                callbackData.amountYield
            );
            return abi.encode(shares);
        } else if (callbackData.actionType == 1) {
            // Remove Liquidity
            (uint256 amountUnderlying, uint256 amountYield) = _removeLiquidityThroughHook(
                callbackData.key,
                callbackData.sender,
                callbackData.shares
            );
            return abi.encode(amountUnderlying, amountYield);
        }
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                        EXTERNAL PUBLIC FUNCTIONS                                //
    /////////////////////////////////////////////////////////////////////////////////////

    function addLiquidity(
        PoolKey calldata key,
        uint256 amountUnderlying,
        uint256 amountYield
    ) external returns (uint256 shares) {
        // Unlock the pool manager manually for adding liquidity to the PM
        // and mint ERC6909 Claim tokens to the hook
        poolManager.unlock(
            abi.encode(
                PMCallbackData({
                    actionType: 0,
                    sender: msg.sender,
                    amountUnderlying: amountUnderlying,
                    amountYield: amountYield,
                    shares: 0,
                    key: key
                })
            )
        );
    }

    function removeLiquidity(
        PoolKey calldata key,
        uint256 shares
    ) external returns (uint256 amountUnderlying, uint256 amountYield) {
        // Unlock the pool manager manually for removing liquidity from the PM
        // and burn ERC6909 Claim tokens to remove the liquidity
        poolManager.unlock(
            abi.encode(
                PMCallbackData({
                    actionType: 1,
                    sender: msg.sender,
                    amountUnderlying: 0,
                    amountYield: 0,
                    shares: shares,
                    key: key
                })
            )
        );
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                         EXTERNAL ADMIN FUNCTIONS                                //
    /////////////////////////////////////////////////////////////////////////////////////

    function registerPool(PoolKey calldata key, address yieldToken) external onlyOwner {
        PoolId id = key.toId();

        if (address(key.hooks) != address(this)) revert InvalidHook();

        address underlying = address(YieldToken(yieldToken).UNDERLYING_TOKEN());
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        bool isValidPair = (token0 == yieldToken && token1 == underlying) ||
            (token1 == yieldToken && token0 == underlying);

        if (!isValidPair) revert InvalidCurrency();

        registeredYieldTokens[id] = yieldToken;
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

    function _addLiquidityThroughHook(
        PoolKey memory key,
        address sender,
        uint256 amountUnderlying,
        uint256 amountYield
    ) internal returns (uint256 shares) {
        PoolId id = key.toId();
        MarketState storage state = marketStates[id];

        // Validations
        if (state.maturity == 0) revert MarketNotInitialized();
        if (state.totalLpSupply == 0 && sender != owner()) revert OnlyOwnerCanInitializeLiquidity();

        if (block.timestamp >= state.maturity) revert MarketExpired();
        if (amountUnderlying == 0 || amountYield == 0) revert InvalidAmount();

        if (state.totalLpSupply == 0) {
            shares = FixedPointMathLib.sqrt(amountUnderlying * amountYield);
        } else {
            // Calculate shares based on the ratio
            uint256 shareU = (amountUnderlying * state.totalLpSupply) / state.reserveUnderlying;
            uint256 shareY = (amountYield * state.totalLpSupply) / state.reserveYield;
            shares = shareU < shareY ? shareU : shareY;
        }

        if (shares == 0) revert InvalidAmount();

        // Update state
        state.reserveUnderlying += amountUnderlying.toUint128();
        state.reserveYield += amountYield.toUint128();
        state.totalLpSupply += shares.toUint128();

        uint256 amount0;
        uint256 amount1;

        if (Currency.unwrap(key.currency0) == state.underlyingToken) {
            // Currency0 is Underlying, Currency1 is YieldToken
            amount0 = amountUnderlying;
            amount1 = amountYield;
        } else {
            // Currency1 is Underlying, Currency0 is YieldToken
            amount0 = amountYield;
            amount1 = amountUnderlying;
        }

        // Create a debit of `amountEach` of each currency with the Pool Manager
        // `burn` = `false` i.e. we're actually transferring tokens, not burning ERC-6909 Claim Tokens
        key.currency0.settle(poolManager, sender, amount0, false);
        key.currency1.settle(poolManager, sender, amount1, false);

        // Since we didn't go through the regular "modify liquidity" flow,
        // the PM just has a debit of amount0 and amount1 of the currency from us
        // We can, in exchange, get back ERC-6909 claim tokens for each currency
        // to create a credit of each currency to us that balances out the debit

        // We will store those claim tokens with the hook, so when swaps take place
        // liquidity from our hook can be used by minting/burning claim tokens the hook owns
        // true = mint claim tokens for the hook, equivalent to money we just deposited to the PM
        key.currency0.take(poolManager, address(this), amount0, true);
        key.currency1.take(poolManager, address(this), amount1, true);

        // Mint LP tokens (ERC6909)
        _mint(sender, uint256(PoolId.unwrap(id)), shares);
    }

    function _removeLiquidityThroughHook(
        PoolKey memory key,
        address sender,
        uint256 shares
    ) internal returns (uint256 amountUnderlying, uint256 amountYield) {
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

        uint256 amount0;
        uint256 amount1;

        if (Currency.unwrap(key.currency0) == state.underlyingToken) {
            // Currency0 is Underlying, Currency1 is YieldToken
            amount0 = amountUnderlying;
            amount1 = amountYield;
        } else {
            // Currency1 is Underlying, Currency0 is YieldToken
            amount0 = amountYield;
            amount1 = amountUnderlying;
        }

        // We need to pay the PM the erc6909 tokens we hold for the liquidity being removed
        key.currency0.settle(poolManager, sender, amount0, true);
        key.currency1.settle(poolManager, sender, amount1, true);

        // Now, the PM has a credit of amount0 and amount1 of the currency to us
        // We can take actual tokens from the PM to balance out that credit
        key.currency0.take(poolManager, address(this), amount0, false);
        key.currency1.take(poolManager, address(this), amount1, false);
    }
}
