// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IYieldOracle {
    /**
     * @notice Returns the current annualized rate (scaled by 1e18).
     * @dev For example, 5% APY = 0.05e18.
     */
    function getRate() external view returns (uint256);
}
