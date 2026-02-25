// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC4626 is ERC4626 {
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_
    ) ERC4626(asset_) ERC20(name_, symbol_) {}

    /// @notice Simulate yield by minting tokens directly to this vault
    function simulateYield(uint256 amount) external {
        ERC20(asset()).transferFrom(msg.sender, address(this), amount);
    }

    /// @notice Simulate bad debt by burning tokens from this vault
    function simulateLoss(uint256 amount) external {
        // This will burn tokens from the vault's balance to simulate loss
        MockERC20(asset()).burn(address(this), amount);
    }
}

// Re-export MockERC20 interface for burns
interface MockERC20 {
    function burn(address from, uint256 amount) external;
}
