// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IYieldSource
/// @notice Interface mirroring the ERC4626 tokenized vault standard
interface IYieldSource {
    
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /// @notice Returns the address of the underlying asset token.
    function asset() external view returns (address assetTokenAddress);

    /// @notice Returns the total amount of the underlying asset managed by the vault.
    function totalAssets() external view returns (uint256 totalManagedAssets);

    /// @notice Deposits `assets` of the underlying token and mints shares to `receiver`.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// @notice Mints exactly `shares` vault shares to `receiver` by depositing assets.
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    /// @notice Burns shares from `owner` and sends exactly `assets` to `receiver`.
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    /// @notice Burns exactly `shares` from `owner` and sends assets to `receiver`.
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    /// @notice Returns the amount of shares that would be minted for a given amount of assets.
    function convertToShares(uint256 assets) external view returns (uint256 shares);

    /// @notice Returns the amount of assets that would be redeemed for a given amount of shares.
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /// @notice Simulates the amount of shares produced by a deposit at the current block.
    function previewDeposit(uint256 assets) external view returns (uint256 shares);

    /// @notice Simulates the amount of assets required to mint a given number of shares.
    function previewMint(uint256 shares) external view returns (uint256 assets);

    /// @notice Simulates the amount of shares burned for a withdrawal of assets.
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);

    /// @notice Simulates the amount of assets received for redeeming shares.
    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    /// @notice Returns the maximum amount of assets that can be deposited for `receiver`.
    function maxDeposit(address receiver) external view returns (uint256 maxAssets);

    /// @notice Returns the maximum amount of shares that can be minted for `receiver`.
    function maxMint(address receiver) external view returns (uint256 maxShares);

    /// @notice Returns the maximum amount of assets that can be withdrawn by `owner`.
    function maxWithdraw(address owner) external view returns (uint256 maxAssets);

    /// @notice Returns the maximum amount of shares that can be redeemed by `owner`.
    function maxRedeem(address owner) external view returns (uint256 maxShares);
}
