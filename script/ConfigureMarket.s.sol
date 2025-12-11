// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

import {PlexusYieldHook} from "src/PlexusYieldHook.sol";
import {YieldToken} from "src/YieldToken.sol";

import {MockERC20} from "src/mocks/MockERC20.sol";

import {DeployConfig} from "./DeployConfig.s.sol";

// Configures the existing deployed PlexusYieldHook and YieldToken contracts
contract ConfigureMarket is DeployConfig {
    // Deployment results
    PlexusYieldHook public hook = PlexusYieldHook(PLEXUS_YIELD_HOOK_UNI_SEPOLIA);
    YieldToken public yieldToken = YieldToken(YIELD_TOKEN_MOCK_USDC_UNI_SEPOLIA);
    PoolKey public poolKey;

    // Default pool configuration
    uint24 constant DEFAULT_FEE = 500; // 0.05%
    int24 constant DEFAULT_TICK_SPACING = 60;

    // sqrt(1) * 2^96 for 1:1 initial price
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address underlying = MOCK_USDC_UNI_SEPOLIA;
        yieldToken = YieldToken(YIELD_TOKEN_MOCK_USDC_UNI_SEPOLIA);
        hook = PlexusYieldHook(PLEXUS_YIELD_HOOK_UNI_SEPOLIA);

        address poolManager = getPoolManager();

        uint256 maturity = yieldToken.MATURITY();

        address yieldOracle = YIELD_ORACLE_MOCK_USDC_UNI_SEPOLIA;

        require(underlying != address(0), "UNDERLYING_TOKEN not set");

        console.log("=== Plexus Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("PoolManager:", poolManager);
        console.log("Underlying Token:", underlying);
        console.log("Maturity:", maturity);

        // Step 1: Set oracle if provided
        if (yieldOracle != address(0)) {
            console.log("\n--- Setting YieldOracle ---");
            yieldToken.setOracle(yieldOracle);
            console.log("YieldOracle set to:", yieldOracle);
        }

        // Step 2: Create PoolKey
        console.log("\n--- Creating PoolKey ---");
        poolKey = _createPoolKey(underlying, address(yieldToken), address(hook));
        console.log("PoolKey created");
        console.log("  Currency0:", Currency.unwrap(poolKey.currency0));
        console.log("  Currency1:", Currency.unwrap(poolKey.currency1));

        // Step 3: Register pool with hook
        console.log("\n--- Step 3: Registering Pool ---");
        hook.registerPool(poolKey, address(yieldToken));
        console.log("Pool registered with hook");

        // Step 4: Initialize pool
        console.log("\n--- Step 4: Initializing Pool ---");
        IPoolManager(poolManager).initialize(poolKey, SQRT_PRICE_1_1);
        console.log("Pool initialized");

        // Step 5: Mint Underlying tokens and YT tokens
        console.log("\n--- Step 5: Mint tokens ---");

        MockERC20(underlying).mint(OWNER, 1_000_000 * 1e6);
        MockERC20(underlying).approve(address(yieldToken), type(uint256).max);
        yieldToken.mintSynthetic(50_000 * 1e6, 100_000 * 1e6);
        console.log("Tokens minted");

        // Step 6: Add initial liquidity
        console.log("\n--- Step 6: Adding Initial Liquidity ---");
        // For 5% APY and a period of 1 year: Implied Rate = R_und / R_yield = 0.05
        // So with 100k YT, we need 5k underlying (5,000 / 100,000 = 0.05) ffor 1 year maturity
        // for 3 months maturity, with 100k YT, we need 1250 underlying.
        uint256 initial_liquidity_underlying = 1250 * 1e6; // 5k USDC
        uint256 initial_liquidity_yt = 100_000 * 1e6; // 100k YT

        MockERC20(underlying).approve(address(hook), type(uint256).max);
        yieldToken.approve(address(hook), type(uint256).max);

        hook.addLiquidity(poolKey, initial_liquidity_underlying, initial_liquidity_yt);

        console.log("liquidity initialized");

        // Print summary
        _printDeploymentSummary();
    }

    function _createPoolKey(address underlying, address yt, address hookAddr) internal pure returns (PoolKey memory) {
        // Sort currencies (token0 < token1 by address)
        Currency currency0;
        Currency currency1;

        if (underlying < yt) {
            currency0 = Currency.wrap(underlying);
            currency1 = Currency.wrap(yt);
        } else {
            currency0 = Currency.wrap(yt);
            currency1 = Currency.wrap(underlying);
        }

        return
            PoolKey({
                currency0: currency0,
                currency1: currency1,
                fee: DEFAULT_FEE,
                tickSpacing: DEFAULT_TICK_SPACING,
                hooks: IHooks(hookAddr)
            });
    }

    function _printDeploymentSummary() internal view {
        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("YieldToken:", address(yieldToken));
        console.log("PlexusYieldHook:", address(hook));
        console.log("Pool Currency0:", Currency.unwrap(poolKey.currency0));
        console.log("Pool Currency1:", Currency.unwrap(poolKey.currency1));
        console.log("Pool Fee:", poolKey.fee);
        console.log("Pool TickSpacing:", poolKey.tickSpacing);
        console.log("=========================================");
    }
}
