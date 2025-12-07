// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {LogExpMath} from "./LogExpMath.sol";

/**
 * @title YieldMath
 * @notice Library for calculating swaps in a Yield Space AMM using a custom power invariant.
 * The library is inspired by the Yield Space AMM from the paper Yield Space whitepaper
 * "Yield Space: A New Primitive for Decentralized Finance" (https://yield.is/yieldspace.pdf)
 * and the Stable Pool Math library based on Curve's StableSwap invariant
 * Stableswap Whitepaper: https://docs.curve.fi/references/whitepapers/stableswap/
 * @dev The invariant used is a custom Constant Power Product formula:
 *
 *      R_und * (R_yield ^ t) = k
 *
 * Where:
 * - R_und: Reserve of the Underlying Token
 * - R_yield: Reserve of the Yield Token
 * - t: Normalized time to maturity (1 at start, 0 at maturity)
 * - k: The invariant constant
 *
 * This invariant ensures that as time passes (t -> 0), the price of Yield Tokens approaches the price of Underlying Tokens (1:1).
 * The exponent `t` acts as a discount factor.
 *
 * Derivations:
 *
 * 1. Swap Underlying for Yield (Exact Input):
 *    Given delta_und (amountIn), find delta_yield (amountOut).
 *    New R_und' = R_und + delta_und
 *    k = R_und * (R_yield ^ t) = R_und' * (R_yield' ^ t)
 *    (R_yield' ^ t) = (R_und / R_und') * (R_yield ^ t)
 *    R_yield' = ((R_und / R_und') ^ (1/t)) * R_yield
 *    delta_yield = R_yield - R_yield'
 *
 * 2. Swap Yield for Underlying (Exact Input):
 *    Given delta_yield (amountIn), find delta_und (amountOut).
 *    New R_yield' = R_yield + delta_yield
 *    k = R_und * (R_yield ^ t) = R_und' * (R_yield' ^ t)
 *    R_und' = R_und * (R_yield / R_yield') ^ t
 *    delta_und = R_und - R_und'
 *
 * Note: All calculations use fixed-point arithmetic with 18 decimals (WAD).
 */
library YieldMath {
    using FixedPointMathLib for uint256;
    using LogExpMath for uint256;

    error InsufficientLiquidity();

    /**
     * @notice Calculates the amount of tokens received for a given input amount.
     * @param rUnd Current reserve of Underlying Token
     * @param rYield Current reserve of Yield Token
     * @param isInputUnderlying True if selling Underlying, False if selling Yield
     * @param amountIn Amount of tokens being sold
     * @param t Normalized time to maturity (scaled by 1e18)
     * @return amountOut Amount of tokens received
     * @return newRUnd New reserve of Underlying Token
     * @return newRYield New reserve of Yield Token
     */
    function computeOutGivenExactIn(
        uint256 rUnd,
        uint256 rYield,
        bool isInputUnderlying,
        uint256 amountIn,
        uint256 t
    ) internal pure returns (uint256 amountOut, uint256 newRUnd, uint256 newRYield) {
        if (isInputUnderlying) {
            // Sell Underlying -> Buy Yield
            // Formula: R_yield' = R_yield * (R_und / R_und') ^ (1/t)

            newRUnd = rUnd + amountIn;

            // ratio = R_und / R_und' (< 1)
            // Round UP the ratio to minimize the resulting R_yield' (which maximizes the amount taken from pool? No wait)
            // We want to MINIMIZE amountOut.
            // amountOut = R_yield - R_yield'
            // To minimize amountOut, we need to MAXIMIZE R_yield'.
            // To maximize R_yield', we need to maximize the factor (ratio ^ exponent).
            // So we round ratio UP.
            uint256 ratio = rUnd.divWadUp(newRUnd);

            // exponent = 1/t (t has 18 decimals of precvision)
            uint256 exponent = (1e18 * 1e18) / t;

            uint256 factor = ratio.pow(exponent);

            newRYield = rYield.mulWadDown(factor);
            amountOut = rYield - newRYield;
        } else {
            // Sell Yield -> Buy Underlying
            // Formula: R_und' = R_und * (R_yield / R_yield') ^ t

            newRYield = rYield + amountIn;

            // ratio = R_yield / R_yield' (< 1)
            uint256 ratio = rYield.divWadUp(newRYield);

            // factor = ratio ^ t
            uint256 factor = ratio.pow(t);

            // newRUnd = R_und * factor
            newRUnd = rUnd.mulWadDown(factor);
            amountOut = rUnd - newRUnd;
        }
    }

    /**
     * @notice Calculates the amount of tokens required for a given output amount.
     * @param rUnd Current reserve of Underlying Token
     * @param rYield Current reserve of Yield Token
     * @param isOutputUnderlying True if buying Underlying, False if buying Yield
     * @param amountOut Amount of tokens to receive
     * @param t Normalized time to maturity (scaled by 1e18)
     * @return amountIn Amount of tokens required
     * @return newRUnd New reserve of Underlying Token
     * @return newRYield New reserve of Yield Token
     */
    function computeInGivenExactOut(
        uint256 rUnd,
        uint256 rYield,
        bool isOutputUnderlying,
        uint256 amountOut,
        uint256 t
    ) internal pure returns (uint256 amountIn, uint256 newRUnd, uint256 newRYield) {
        if (isOutputUnderlying) {
            // Buy Underlying -> Sell Yield
            // We need to find amountIn (Yield) to get amountOut (Underlying)
            // Formula: R_yield' = R_yield * (R_und / R_und') ^ (1/t)
            // Where R_und' = R_und - amountOut

            if (amountOut >= rUnd) revert InsufficientLiquidity();
            newRUnd = rUnd - amountOut;

            // ratio = R_und / R_und' (> 1)
            // Round UP to maximize amountIn (protect pool)
            uint256 ratio = rUnd.divWadUp(newRUnd);

            uint256 exponent = (1e18 * 1e18) / t;
            uint256 factor = ratio.pow(exponent);

            // newRYield = R_yield * factor
            // Round UP to maximize new reserve, which maximizes amountIn
            newRYield = rYield.mulWadUp(factor);
            amountIn = newRYield - rYield;
        } else {
            // Buy Yield -> Sell Underlying
            // We need to find amountIn (Underlying) to get amountOut (Yield)
            // Formula: R_und' = R_und * (R_yield / R_yield') ^ t
            // Where R_yield' = R_yield - amountOut

            if (amountOut >= rYield) revert InsufficientLiquidity();
            newRYield = rYield - amountOut;

            // ratio = R_yield / R_yield' (> 1)
            uint256 ratio = rYield.divWadUp(newRYield);

            uint256 factor = ratio.pow(t);

            // newRUnd = R_und * factor
            newRUnd = rUnd.mulWadUp(factor);
            amountIn = newRUnd - rUnd;
        }
    }
}
