// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IYieldOracle} from "src/interfaces/IYieldOracle.sol";

contract MockYieldOracle is IYieldOracle {
    uint256 public rate;

    function setRate(uint256 _rate) external {
        rate = _rate;
    }

    function getRate() external view override returns (uint256) {
        return rate;
    }
}
