// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import {
    ERC4626
} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IYieldSource} from "./Yield/IYieldSource.sol";
import {IPrincipalOnlyVault} from "./IPrincipalOnlyVault.sol";

/// @title PrincipalOnlyVault
/// @notice ERC4626 vault that deploys assets to yield source while keeping yield as protocol revenue.
/// @author oot2k, SC Audit Studio, scauditstudio.com
contract PrincipalOnlyVault is ERC4626, AccessControl, IPrincipalOnlyVault {
    bytes32 public constant YIELD_MANAGER_ROLE =
        keccak256("YIELD_MANAGER_ROLE");
    uint256 public constant BPS = 10000;
    uint256 public principalDeposited;
    uint256 public targetBufferBps = 500; // 5% buffer

    IYieldSource public yieldSource;
    address public treasury;

    /// @dev Reverts after the function body if the vault is insolvent.
    modifier checkSolvency() {
        _;
        _checkSolvency();
    }

    /// @param name_ ERC20 share token name.
    /// @param symbol_ ERC20 share token symbol.
    /// @param asset_ Underlying ERC20 asset.
    /// @param initialTargetBufferBps Percentage of principal to keep idle (in bps).
    /// @param initialTreasury Address that receives claimed yield.
    /// @param initialYieldSource Yield strategy contract (can be address(0) to disable).
    constructor(
        string memory name_,
        string memory symbol_,
        IERC20 asset_,
        uint256 initialTargetBufferBps,
        address initialTreasury,
        IYieldSource initialYieldSource
    ) ERC4626(asset_) ERC20(name_, symbol_) {
        if (initialTreasury == address(0)) revert TreasuryZeroAddress();
        if (initialTargetBufferBps >= BPS) revert TargetBufferBpsTooHigh();

        _grantRole(YIELD_MANAGER_ROLE, _msgSender());
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        targetBufferBps = initialTargetBufferBps;
        yieldSource = initialYieldSource;
        treasury = initialTreasury;
    }

    /// @notice Returns the amount of the underlying asset sitting idle in this contract.
    function idleAssets() public view virtual returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /// @notice Total assets reported to ERC4626, capped at `principalDeposited` to keep the share price stable.
    function totalAssets() public view virtual override returns (uint256) {
        uint256 assets = totalAssetsWithYield();
        if (assets > principalDeposited) {
            assets = principalDeposited;
        }
        return assets;
    }

    /// @notice Returns the true asset balance including accrued yield in the yield source.
    function totalAssetsWithYield() public view virtual returns (uint256) {
        if (address(yieldSource) == address(0)) {
            return idleAssets();
        }
        uint256 yieldSourceAssets = IYieldSource(yieldSource).maxWithdraw(
            address(this)
        );
        return idleAssets() + yieldSourceAssets;
    }

    /// @notice Redeems `shares` for assets, pulling from the yield source if idle liquidity is insufficient.
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        uint256 availableLiquidity = idleAssets();
        uint256 assets = previewRedeem(shares);

        if (availableLiquidity < assets) {
            uint256 missing = assets - availableLiquidity;
            _withdrawFromSource(missing);
            //Might burn more shares due to rounding, should be balanced by previewWithdraw as it rounds up
        }

        return super.redeem(shares, receiver, owner);
    }

    /// @notice Withdraws `assets`, pulling from the yield source if idle liquidity is insufficient.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        uint256 availableLiquidity = idleAssets();

        if (availableLiquidity < assets) {
            uint256 missing = assets - availableLiquidity;
            _withdrawFromSource(missing);
            //Might burn more shares due to rounding, should be balanced by previewWithdraw as it rounds up
        }

        return super.withdraw(assets, receiver, owner);
    }

    /// @notice Rebalances idle assets to match `targetBufferBps`, deploying excess or withdrawing shortfall.
    function rebalance() external checkSolvency onlyRole(YIELD_MANAGER_ROLE) {
        uint256 idle = idleAssets();
        uint256 targetBuffer = (principalDeposited * targetBufferBps) / BPS;

        uint256 withdrawn;
        uint256 deployed;

        if (idle < targetBuffer) {
            withdrawn = targetBuffer - idle;
            _withdrawFromSource(withdrawn);
        } else if (idle > targetBuffer) {
            deployed = idle - targetBuffer;
            _depositToSource(deployed);
        }

        emit Rebalanced(withdrawn, deployed);
    }

    /// @notice Withdraws `amount` of accrued yield from the source and sends it to the treasury.
    /// @param amount Amount of yield to claim (in underlying asset units).
    function claimYield(
        uint256 amount
    ) external checkSolvency onlyRole(YIELD_MANAGER_ROLE) {
        uint256 claimable = totalAssetsWithYield() - principalDeposited;
        amount = amount > claimable ? claimable : amount;

        if(amount == 0){
            revert NoYield();
        }

        _withdrawFromSource(amount);
        SafeERC20.safeTransfer(IERC20(asset()), treasury, amount);
        emit YieldClaimed(amount, treasury);
    }

    /// @notice Emergency-only: withdraws `amount` from the yield source without a solvency check.
    /// @param amount Amount to withdraw from the yield source.
    function emergencyWithdraw(
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _withdrawFromSource(amount);
        emit EmergencyWithdrawal(amount);
    }

    /// @notice Replaces the yield source. Withdraws all assets from the old source unless `skipWithdraw` is set.
    /// @param newYieldSource New yield strategy (can be address(0) to disable).
    /// @param skipWithdraw If true, skips withdrawing from the current source.
    function changeYieldSource(
        IYieldSource newYieldSource,
        bool skipWithdraw
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(yieldSource) != address(0)) {
            uint256 yieldSourceAssets = IYieldSource(yieldSource).maxWithdraw(
                address(this)
            );
            if (!skipWithdraw && yieldSourceAssets > 0) {
                _withdrawFromSource(yieldSourceAssets);
            }
        }
        IYieldSource oldSource = yieldSource;
        yieldSource = newYieldSource;
        emit YieldSourceChanged(oldSource, newYieldSource);
    }

    /// @notice Updates the target idle buffer percentage.
    /// @param newTargetBufferBps New buffer in basis points (must be < 10 000).
    function setTargetBufferBps(
        uint256 newTargetBufferBps
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTargetBufferBps >= BPS) revert TargetBufferBpsTooHigh();
        uint256 oldBps = targetBufferBps;
        targetBufferBps = newTargetBufferBps;
        emit TargetBufferBpsUpdated(oldBps, newTargetBufferBps);
    }

    /// @notice Updates the treasury address.
    /// @param newTreasury New treasury (must not be address(0)).
    function setTreasury(
        address newTreasury
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert TreasuryZeroAddress();
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    ///@dev Override deposit to add principal tracking.
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        principalDeposited = principalDeposited + assets;
        super._deposit(caller, receiver, assets, shares);
    }

    ///@dev Override withdraw to add principal tracking.
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        principalDeposited = principalDeposited - assets;
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /// @dev Approves and deposits `amount` of the underlying asset into the yield source.
    function _depositToSource(uint256 amount) internal {
        SafeERC20.forceApprove(IERC20(asset()), address(yieldSource), amount);
        IYieldSource(yieldSource).deposit(amount, address(this));
    }

    /// @dev Withdraws up to `amount` from the yield source (capped at available balance).
    function _withdrawFromSource(uint256 amount) internal {
        uint256 yieldSourceAssets = IYieldSource(yieldSource).maxWithdraw(
            address(this)
        );
        if (amount > yieldSourceAssets) {
            amount = yieldSourceAssets;
        }
        IYieldSource(yieldSource).withdraw(
            amount,
            address(this),
            address(this)
        );
    }

    /// @dev Reverts with `Insolvent` if total assets (including yield source) are below principal.
    function _checkSolvency() internal view {
        if (totalAssetsWithYield() < principalDeposited) revert Insolvent();
    }
}
