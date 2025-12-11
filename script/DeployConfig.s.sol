// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";

/// @title DeployConfig
/// @notice Shared configuration for deployment scripts
abstract contract DeployConfig is Script {
    // CREATE2 Deployer Proxy (standard across all EVM chains)
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address constant OWNER = 0xb93E9D76C100453886e3dC51Aab4847Fd03bd3F1;

    // Unichain Sepolia
    address constant POOL_MANAGER_UNICHAIN_SEPOLIA = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;

    // Deployed contracts on Unichain Sepolia
    address constant MOCK_USDC_UNI_SEPOLIA = 0xa033Fcb23bBE07621B17AdA4E69E4CdDCd8531dF;
    address constant YIELD_TOKEN_MOCK_USDC_UNI_SEPOLIA = 0x27c08fCA881d009a9F4a11a140C02b3FBa4A2e88;
    address constant PLEXUS_YIELD_HOOK_UNI_SEPOLIA = 0x89bf534a9f43EA428000858a069ef3C3b960aa88;
    address constant YIELD_ORACLE_MOCK_USDC_UNI_SEPOLIA = 0x218aF9861135faDF0D9e2529096b1f4146143adF;

    /// @notice Get the PoolManager address for the current chain
    function getPoolManager() internal view returns (address) {
        uint256 chainId = block.chainid;

        if (chainId == 1301) {
            // Unichain Sepolia
            return POOL_MANAGER_UNICHAIN_SEPOLIA;
        } else {
            revert("DeployConfig: Unsupported chain");
        }
    }

    /// @notice Get a default maturity timestamp (3 months from now)
    function getDefaultMaturity() internal view returns (uint256) {
        return block.timestamp + 90 days;
    }
}
