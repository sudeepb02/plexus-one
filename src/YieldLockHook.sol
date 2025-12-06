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
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {YieldToken} from "./YieldToken.sol";

contract YieldLockHook is BaseHook, Ownable {
    using PoolIdLibrary for PoolKey;
    using SafeCast for int256;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;
    using CurrencyLibrary for Currency;

    error InvalidCurrency();
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
    mapping(PoolId => mapping(address => uint256)) public lpBalances;

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
}
