// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {YieldToken} from "src/YieldToken.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";

import {DeployConfig} from "./DeployConfig.s.sol";

contract DeployYieldToken is DeployConfig {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        uint256 maturity = block.timestamp + 90 days;
        address underlyingToken = address(new MockERC20("Mock USDC", "mockUSDC", 6));

        string memory name = "Plexus Yield Mock USDC 90D";
        string memory symbol = "pyMockUSDC-90D";

        console.log("Deploying YieldToken...");
        console.log("  Underlying:", underlyingToken);
        console.log("  Maturity:", maturity);
        console.log("  Name:", name);
        console.log("  Symbol:", symbol);

        YieldToken yieldToken = new YieldToken(name, symbol, underlyingToken, maturity);

        vm.stopBroadcast();

        console.log("YieldToken deployed at:", address(yieldToken));
    }

    /// @notice Deploy with explicit parameters
    function deploy(
        string memory name,
        string memory symbol,
        address underlying,
        uint256 maturity
    ) public returns (YieldToken yieldToken) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        yieldToken = new YieldToken(name, symbol, underlying, maturity);
        vm.stopBroadcast();

        console.log("YieldToken deployed at:", address(yieldToken));
    }
}
