// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {MockYieldOracle} from "src/mocks/MockYieldOracle.sol";

import {DeployConfig} from "./DeployConfig.s.sol";

contract DeployYieldOracle is DeployConfig {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MockYieldOracle yieldOracle = new MockYieldOracle();

        vm.stopBroadcast();

        console.log("yieldOracle deployed at:", address(yieldOracle));
    }
}
