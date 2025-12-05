// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// V4 imports
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {IPoolManager, ModifyLiquidityParams} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {YieldToken} from "./YieldToken.sol";

contract YieldLockHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using SafeCast for int256;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;
    using CurrencyLibrary for Currency;

    error InvalidCurrency();
    error MarketExpired();

    address public immutable YIELD_TOKEN;
    address public immutable UNDERLYING_TOKEN;

    constructor(IPoolManager _manager, address _yieldToken, address _underlyingToken) BaseHook(_manager) {
        YIELD_TOKEN = _yieldToken;
        UNDERLYING_TOKEN = _underlyingToken;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return
            Hooks.Permissions({
                beforeInitialize: true, //
                afterInitialize: false,
                beforeAddLiquidity: true, //
                beforeRemoveLiquidity: true, //
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true, //
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true, //
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function _beforeInitialize(address, PoolKey calldata key, uint160) internal override returns (bytes4) {
        // Validate that YT is either currency0 or currency1
        if (Currency.unwrap(key.currency0) != YIELD_TOKEN && Currency.unwrap(key.currency1) != YIELD_TOKEN) {
            revert InvalidCurrency();
        }
        // Validate that UNDERLYING_TOKEN is the other currency
        if (Currency.unwrap(key.currency0) != UNDERLYING_TOKEN && Currency.unwrap(key.currency1) != UNDERLYING_TOKEN) {
            revert InvalidCurrency();
        }

        // Validate that the market has not expired
        if (block.timestamp >= YieldToken(YIELD_TOKEN).MATURITY()) {
            revert MarketExpired();
        }

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
}
