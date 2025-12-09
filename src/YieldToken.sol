// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IYieldOracle} from "./interfaces/IYieldOracle.sol";

contract YieldToken is ERC20, Ownable {
    using SafeERC20 for IERC20;

    address public hook;
    IYieldOracle public oracle;

    IERC20 public immutable UNDERLYING_TOKEN;
    uint256 public immutable MATURITY;

    // Global State
    uint256 public globalIndex; // The cumulative yield index
    uint256 public lastUpdated; // Timestamp of last index update

    // Vaults (Short Positions with deposited collateral)
    struct Vault {
        uint256 collateral; // Amount of Underlying Token locked
        uint256 mintedAmount; // Amount of Yield Token minted (Notional)
    }

    mapping(address => Vault) public vaults;

    // Constants and Configs
    uint256 public constant INITIAL_INDEX = 1e18;
    // Minimum collateral required per unit of YT minted
    // (for ex, 0.1e18 = 10% of Notional ie. 0.1 ETH required to mint 1 YT ETH)
    // This acts as the  collateral (maintenance margin) for the future yield liability to long YT holders
    uint256 public constant MIN_COLLATERAL_RATIO = 0.1e18;

    // Penalty paid to liquidators (5%)
    uint256 public constant LIQUIDATION_PENALTY = 0.05e18;

    error MarketExpired();
    error MarketNotExpired();
    error InvalidAmount();
    error HookAlreadySet();
    error OnlyHook();
    error SolvencyCheckFailed();
    error UserIsSolvent();

    constructor(
        string memory name,
        string memory symbol,
        address _underlying,
        uint256 _maturity
    ) ERC20(name, symbol) Ownable(msg.sender) {
        UNDERLYING_TOKEN = IERC20(_underlying);
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

    function updateGlobalIndex() external {
        _updateGlobalIndex();
    }

    function calculateAccruedYield(uint256 amountYt) external view returns (uint256) {
        return _calculateAccruedYield(amountYt);
    }

    function isSolvent(address user) external view returns (bool) {
        return _isSolvent(user);
    }

    ////////////////////// SHORT POSITIONS (ISSUANCE OF YT) /////////////////////////////

    function mintSynthetic(uint256 amountCollateral, uint256 amountYt) external {
        _updateGlobalIndex();

        if (block.timestamp >= MATURITY) revert MarketExpired();

        Vault storage vault = vaults[msg.sender];

        // 1. Transfer Collateral to the contract
        if (amountCollateral > 0) {
            UNDERLYING_TOKEN.safeTransferFrom(msg.sender, address(this), amountCollateral);
            vault.collateral += amountCollateral;
        }

        // 2. Mint YT (Increase Notional supply by creating a debt position)
        if (amountYt > 0) {
            vault.mintedAmount += amountYt;
            _mint(msg.sender, amountYt);
        }

        if (!_isSolvent(msg.sender)) revert SolvencyCheckFailed();
    }

    function burnSynthetic(uint256 amountYt, uint256 amountCollateral) external {
        _updateGlobalIndex();

        Vault storage vault = vaults[msg.sender];

        // 1. Burn YT (Decrease Notional supply/ repay Debt)
        if (amountYt > 0) {
            if (vault.mintedAmount < amountYt) revert InvalidAmount();
            vault.mintedAmount -= amountYt;
            _burn(msg.sender, amountYt);
        }

        // 2. Withdraw Collateral
        if (amountCollateral > 0) {
            if (vault.collateral < amountCollateral) revert InvalidAmount();
            vault.collateral -= amountCollateral;
            UNDERLYING_TOKEN.safeTransfer(msg.sender, amountCollateral);
        }

        if (vault.mintedAmount > 0 && !_isSolvent(msg.sender)) revert SolvencyCheckFailed();
    }

    ////////////////////// LONG POSITIONS (YIELD REDEMPTION) ////////////////////////////

    function redeemYield(uint256 amountYt) external {
        _updateGlobalIndex();

        if (block.timestamp < MATURITY) revert MarketNotExpired();

        // Payout = amountYt * (FinalIndex - InitialIndex)
        uint256 payout = _calculateAccruedYield(amountYt);

        _burn(msg.sender, amountYt);

        UNDERLYING_TOKEN.safeTransfer(msg.sender, payout);
    }

    function settleShort() external {
        _updateGlobalIndex();

        if (block.timestamp < MATURITY) revert MarketNotExpired();

        Vault storage vault = vaults[msg.sender];

        // Calculate Final Debt (money owed to Long YT holders,
        // stored in the contract for future claim by long YT holders
        uint256 debt = _calculateAccruedYield(vault.mintedAmount);

        uint256 remainingCollateral = 0;
        if (vault.collateral > debt) {
            remainingCollateral = vault.collateral - debt;
        }
        // The `debt` amount stays in the contract to fund `redeemYield`.

        // Clear Vault state
        vault.collateral = 0;
        vault.mintedAmount = 0;

        if (remainingCollateral > 0) {
            UNDERLYING_TOKEN.safeTransfer(msg.sender, remainingCollateral);
        }
    }

    ////////////////////// LIQUIDATE POSITIONS (PUBLIC) ////////////////////////////

    function liquidate(address user, uint256 amountYt) external {
        _updateGlobalIndex();

        if (_isSolvent(user)) revert UserIsSolvent();

        Vault storage vault = vaults[user];
        if (amountYt > vault.mintedAmount) amountYt = vault.mintedAmount;

        // Calculate the value of the debt being repaid
        // Debt Value = Accrued Yield (Intrinsic Value)
        uint256 accruedValue = _calculateAccruedYield(amountYt);

        // Liquidator Reward = Debt Value + Penalty
        // The penalty is calculated on the accrued value, not the notional (YT balance).
        uint256 reward = accruedValue + (accruedValue * LIQUIDATION_PENALTY) / 1e18;

        // The contract should not pay more than the users total available collateral
        // else it will become insolvent for the users that withdraw last.
        if (reward > vault.collateral) {
            reward = vault.collateral;
        }

        // 1. Burn Liquidator's YT (Repay Debt)
        // Instead of transferring YT from liquidator, we burn directly from liquidator's balance
        vault.mintedAmount -= amountYt;
        _burn(msg.sender, amountYt);

        // 2. Seize Collateral
        vault.collateral -= reward;
        UNDERLYING_TOKEN.safeTransfer(msg.sender, reward);
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

    function _calculateAccruedYield(uint256 amountYt) internal view returns (uint256) {
        if (globalIndex <= INITIAL_INDEX) return 0;
        return (amountYt * (globalIndex - INITIAL_INDEX)) / 1e18;
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

    function _isSolvent(address user) internal view returns (bool) {
        Vault storage vault = vaults[user];
        if (vault.mintedAmount == 0) return true;

        // Liability = Accrued Debt + Maintenance Margin
        uint256 accruedDebt = _calculateAccruedYield(vault.mintedAmount);

        // Maintenance Margin = Minted * Ratio
        // This ensures there is always a buffer for future yield growth
        uint256 margin = (vault.mintedAmount * MIN_COLLATERAL_RATIO) / 1e18;

        return vault.collateral >= (accruedDebt + margin);
    }
}
