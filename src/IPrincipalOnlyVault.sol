// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IYieldSource} from "./Yield/IYieldSource.sol";

interface IPrincipalOnlyVault {
    // ──────────────────────────── Events ────────────────────────────

    /// @notice Emitted when the vault is rebalanced.
    event Rebalanced(uint256 amountWithdrawn, uint256 amountDeployed);

    /// @notice Emitted when accrued yield is claimed to the treasury.
    event YieldClaimed(uint256 amount, address indexed treasury);

    /// @notice Emitted when funds are withdrawn in an emergency.
    event EmergencyWithdrawal(uint256 amount);

    /// @notice Emitted when the yield source is changed.
    event YieldSourceChanged(
        IYieldSource indexed oldSource,
        IYieldSource indexed newSource
    );

    /// @notice Emitted when the target buffer bps is updated.
    event TargetBufferBpsUpdated(uint256 oldBps, uint256 newBps);

    /// @notice Emitted when the treasury address is updated.
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    // ──────────────────────────── Errors ────────────────────────────

    /// @notice Thrown when the treasury address is the zero address.
    error TreasuryZeroAddress();

    /// @notice Thrown when the target buffer bps exceeds the maximum (100%).
    error TargetBufferBpsTooHigh();

    /// @notice Thrown when the vault becomes insolvent.
    error Insolvent();

    // ──────────────────────── View functions ────────────────────────

    /// @notice Returns the amount of assets held idle in the vault.
    function idleAssets() external view returns (uint256);

    /// @notice Returns the total assets including yield source balance.
    function totalAssetsWithYield() external view returns (uint256);

    /// @notice Returns the total principal deposited by users.
    function principalDeposited() external view returns (uint256);

    /// @notice Returns the current target buffer in basis points.
    function targetBufferBps() external view returns (uint256);

    /// @notice Returns the current yield source.
    function yieldSource() external view returns (IYieldSource);

    /// @notice Returns the current treasury address.
    function treasury() external view returns (address);

    // ──────────────────── Mutative functions ────────────────────────

    /// @notice Rebalances the vault to match the target buffer.
    function rebalance() external;

    /// @notice Claims accrued yield and sends it to the treasury.
    function claimYield(uint256 amount) external;

    /// @notice Emergency withdrawal from the yield source (no solvency check).
    function emergencyWithdraw(uint256 amount) external;

    /// @notice Changes the yield source, optionally withdrawing from the old one.
    function changeYieldSource(
        IYieldSource newYieldSource,
        bool skipWithdraw
    ) external;

    /// @notice Sets a new target buffer in basis points.
    function setTargetBufferBps(uint256 newTargetBufferBps) external;

    /// @notice Sets a new treasury address.
    function setTreasury(address newTreasury) external;
}
