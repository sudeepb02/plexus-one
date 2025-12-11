// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

import {PlexusYieldHook} from "../src/PlexusYieldHook.sol";

import {DeployConfig} from "./DeployConfig.s.sol";

/// @title DeployPlexusYieldHook
/// @notice Deploys the PlexusYieldHook contract using CREATE2 with a mined salt
contract DeployPlexusYieldHook is DeployConfig {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Get the PoolManager address for the current chain
        address poolManager = getPoolManager();

        console.log("Deploying PlexusYieldHook...");
        console.log("  Chain ID:", block.chainid);
        console.log("  PoolManager:", poolManager);

        // Hooks that PlexusYieldHook requires
        // These must match the flags returned by getHookPermissions()
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );

        console.log("  Required flags:", uint256(flags));

        // Prepare constructor arguments
        bytes memory constructorArgs = abi.encode(poolManager, OWNER);

        // Mine a salt that produces a hook address with the correct flags
        console.log("Mining salt for hook address...");
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(PlexusYieldHook).creationCode,
            constructorArgs
        );

        console.log("  Found hook address:", hookAddress);
        console.log("  Salt:", vm.toString(salt));

        // Deploy the hook using CREATE2
        vm.startBroadcast(deployerPrivateKey);

        PlexusYieldHook hook = new PlexusYieldHook{salt: salt}(IPoolManager(poolManager), OWNER);

        vm.stopBroadcast();

        // Verify the deployed address matches the mined address
        require(address(hook) == hookAddress, "DeployPlexusYieldHook: deployed address does not match mined address");

        console.log("PlexusYieldHook deployed at:", address(hook));
        console.log("  Owner:", hook.owner());
    }

    /// @notice Deploy with explicit PoolManager address (for use in other scripts)
    function deploy(address poolManager) public returns (PlexusYieldHook hook) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );

        bytes memory constructorArgs = abi.encode(poolManager, OWNER);

        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(PlexusYieldHook).creationCode,
            constructorArgs
        );

        vm.startBroadcast(deployerPrivateKey);
        hook = new PlexusYieldHook{salt: salt}(IPoolManager(poolManager), OWNER);
        vm.stopBroadcast();

        require(address(hook) == hookAddress, "DeployPlexusYieldHook: deployed address does not match mined address");

        console.log("PlexusYieldHook deployed at:", address(hook));
    }
}
