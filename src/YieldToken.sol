// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract YieldToken is ERC20, Ownable {
    address public hook;
    address public immutable POOL_MANAGER;
    address public immutable UNDERLYING_TOKEN;
    uint256 public immutable MATURITY;

    error TransferNotAllowed();
    error HookAlreadySet();

    constructor(
        string memory name,
        string memory symbol,
        address _poolManager,
        address _underlying,
        uint256 _maturity
    ) ERC20(name, symbol) Ownable(msg.sender) {
        POOL_MANAGER = _poolManager;
        UNDERLYING_TOKEN = _underlying;
        MATURITY = _maturity;
    }

    function setHook(address _hook) external onlyOwner {
        if (hook != address(0)) revert HookAlreadySet();
        hook = _hook;
        transferOwnership(_hook);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        // Allow minting (from == 0) and burning (to == 0)
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        // Restrict transfers:
        // 1. Hook can move tokens (Liquidity management)
        // 2. PoolManager can move tokens (Swap settlement)
        // 3. Users CANNOT transfer to each other
        if (msg.sender != hook && msg.sender != POOL_MANAGER) {
            revert TransferNotAllowed();
        }

        super._update(from, to, value);
    }
}
