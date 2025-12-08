// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IYieldOracle} from "./interfaces/IYieldOracle.sol";

contract YieldToken is ERC20, Ownable {
    address public hook;
    IYieldOracle public oracle;

    address public immutable POOL_MANAGER;
    address public immutable UNDERLYING_TOKEN;
    uint256 public immutable MATURITY;

    // Global State
    uint256 public globalIndex; // The cumulative yield index
    uint256 public lastUpdated; // Timestamp of last index update

    // Constants and Configs
    uint256 public constant INITIAL_INDEX = 1e18;

    error TransferNotAllowed();
    error HookAlreadySet();
    error OnlyHook();

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

        globalIndex = INITIAL_INDEX;
        lastUpdated = block.timestamp;
    }

    modifier onlyHook() {
        _onlyHook();
        _;
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                        EXTERNAL PUBLIC FUNCTIONS                                //
    /////////////////////////////////////////////////////////////////////////////////////

    function mint(address to, uint256 amount) external onlyHook {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyHook {
        _burn(from, amount);
    }

    function updateGlobalIndex() external {
        _updateGlobalIndex();
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                         EXTERNAL ADMIN FUNCTIONS                                //
    /////////////////////////////////////////////////////////////////////////////////////

    function setHook(address _hook) external onlyOwner {
        if (hook != address(0)) revert HookAlreadySet();
        hook = _hook;
    }

    function setOracle(address _oracle) external onlyOwner {
        oracle = IYieldOracle(_oracle);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    //                         INTERNAL HELPER FUNCTIONS                               //
    /////////////////////////////////////////////////////////////////////////////////////

    // For wrapped modifier onlyHook
    function _onlyHook() internal view {
        if (msg.sender != hook) revert OnlyHook();
    }

    function _update(address from, address to, uint256 value) internal override {
        _updateGlobalIndex();
        super._update(from, to, value);
    }

    function _updateGlobalIndex() internal {
        uint256 currentTime = block.timestamp;
        if (currentTime > MATURITY) currentTime = MATURITY;
        if (currentTime <= lastUpdated) return;

        if (address(oracle) != address(0)) {
            uint256 rate = oracle.getRate(); // Annualized rate with 18 decimals, 5% = 0.05e18
            uint256 timeDelta = currentTime - lastUpdated;

            // Simple Interest Rate Accumulation: Index += Index * Rate * timeDelta
            uint256 interest = (globalIndex * rate * timeDelta) / (1e18 * 365 days);
            globalIndex += interest;
        }

        lastUpdated = currentTime;
    }
}
