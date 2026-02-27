// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {PrincipalOnlyVault} from "../src/PrincipalOnlyVault.sol";
import {IPrincipalOnlyVault} from "../src/IPrincipalOnlyVault.sol";
import {IYieldSource} from "../src/Yield/IYieldSource.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC4626} from "./mocks/MockERC4626.sol";

contract PrincipalOnlyVaultTest is Test {
    PrincipalOnlyVault public vault;
    MockERC20 public asset;
    MockERC4626 public yieldSource;
    
    address public treasury;
    address public alice;
    address public bob;
    
    uint256 constant BUFFER_BPS = 500; // 5%
    uint256 constant INITIAL_MINT = 1_000_000e18;

    function setUp() public {
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        
        // Deploy mock ERC20
        asset = new MockERC20("Test Token", "TEST");
        
        // Deploy mock ERC4626 yield source
        yieldSource = new MockERC4626(asset, "Yield Source", "yTEST");
        
        // Deploy YieldVault
        vault = new PrincipalOnlyVault(
            "Yield Vault Token",
            "yvTEST",
            asset,
            BUFFER_BPS,
            treasury,
            IYieldSource(address(yieldSource))
        );
        
        // Dead deposit to protect against inflation attacks
        uint256 deadDeposit = 1e18;
        asset.mint(address(this), deadDeposit);
        asset.approve(address(vault), deadDeposit);
        uint256 deadShares = vault.deposit(deadDeposit, address(1)); // Burn shares to dead address
        
        // Mint initial tokens to test users
        asset.mint(alice, INITIAL_MINT);
        asset.mint(bob, INITIAL_MINT);
    }
    
    // ═══════════════════════════ Basic Functionality Tests ═══════════════════════════
    
    function test_deposit() public {
        uint256 depositAmount = 1000e18;
        uint256 assetsBefore = vault.totalAssets();

        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        assertEq(shares,depositAmount, "Should mint 1:1 on first deposit");
        assertEq(vault.balanceOf(alice), shares, "Alice should have shares");
        assertEq(vault.principalDeposited(),assetsBefore + depositAmount, "Principal tracking");
        assertEq(vault.totalAssets(),assetsBefore + depositAmount, "Total assets equals deposit");
    }
    
    function test_withdraw() public {
        uint assetsBefore = vault.totalAssets();
        uint256 depositAmount = 1000e18;
        
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        
        uint256 withdrawAmount = 500e18;
        vault.withdraw(withdrawAmount, alice, alice);
        vm.stopPrank();
        
        assertEq(vault.principalDeposited(),assetsBefore + depositAmount - withdrawAmount, "Principal reduced");
        assertEq(asset.balanceOf(alice), INITIAL_MINT - depositAmount + withdrawAmount, "Alice got assets back");
    }
    
    function test_redeem() public {
        uint256 depositAmount = 1000e18;
        
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, alice);
        
        uint256 redeemShares = shares / 2;
        uint256 assetsReceived = vault.redeem(redeemShares, alice, alice);
        vm.stopPrank();
        
        assertEq(assetsReceived, depositAmount / 2, "Should receive proportional assets");
        assertEq(vault.balanceOf(alice), shares - redeemShares, "Shares burned correctly");
    }
    
    function test_rebalance_depositToYield() public {
        uint256 depositAmount = 10_000e18;

        // Alice deposits
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 totalAssets = vault.totalAssets();
        // Target buffer is 5% = 500e18
        // Idle should be 10000e18, so 9500e18 should be deployed
        uint256 expectedDeployed = totalAssets - (totalAssets * BUFFER_BPS / 10000);
        
        vm.expectEmit(true, true, true, true);
        emit IPrincipalOnlyVault.Rebalanced(0, expectedDeployed);
        vault.rebalance();
        
        assertApproxEqAbs(vault.idleAssets(), totalAssets * BUFFER_BPS / 10000, 1, "Buffer maintained");
        assertGt(yieldSource.maxWithdraw(address(vault)), 0, "Assets deployed to yield source");
    }
    
    function test_rebalance_withdrawFromYield() public {
        uint256 depositAmount = 10_000e18;
        
        // Alice deposits and we rebalance
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();
        vault.rebalance();
        
        // Bob deposits more (idle increases)
        uint256 bobDeposit = 5_000e18;
        vm.startPrank(bob);
        asset.approve(address(vault), bobDeposit);
        vault.deposit(bobDeposit, bob);
        vm.stopPrank();
        
        // Now total principal is 15k, target buffer = 750, idle is ~5500
        // Rebalance should deploy more: ~4750
        vault.rebalance();
        
        // Now Alice withdraws 8000 - this depletes idle
        vm.startPrank(alice);
        vault.withdraw(8000e18, alice, alice);
        vm.stopPrank();
        
        // Now idle is very low, rebalance should withdraw from yield source
        uint256 idleBefore = vault.idleAssets();
        vault.rebalance();
        uint256 idleAfter = vault.idleAssets();
        
        assertGt(idleAfter, idleBefore, "Idle increased after rebalancing");
    }
    
    // ═══════════════════════════ Yield Stays With Protocol ═══════════════════════════
    
    function test_withdrawNeverExceedsDeposit_withYield() public {
        uint256 depositAmount = 10_000e18;
        uint assetsBefore = vault.totalAssets();

        // Alice deposits
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();
        
        // Rebalance to deploy assets
        vault.rebalance();
        
        // Simulate 20% yield accrual - mint tokens directly to yield source
        uint256 yieldAmount = 2_000e18;
        asset.mint(address(yieldSource), yieldAmount);
        
        // Alice tries to withdraw all - should only get original principal
        vm.startPrank(alice);
        uint256 assetsReceived = vault.redeem(shares, alice, alice);
        vm.stopPrank();
        
        assertEq(assetsReceived, depositAmount, "Alice only gets principal back");
        assertLt(assetsReceived, depositAmount + yieldAmount, "Yield stays in protocol");
        
        // Verify yield is still in the system
        uint256 totalWithYield = vault.totalAssetsWithYield();
        assertEq(totalWithYield, assetsBefore + yieldAmount - 1, "Yield remains in vault/source");
    }
    
    function test_sharePrice_neverIncreases() public {
        uint256 depositAmount = 10_000e18;
        uint256 vaultAssetsBefore = vault.totalAssets();
        // Alice deposits
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        vault.rebalance();
        
      
        // Simulate yield
        uint256 yieldAmount = 5_000e18;
        asset.mint(address(yieldSource), yieldAmount);
        
        // totalAssets should still equal principalDeposited (share price unchanged)
        assertEq(vault.totalAssets(),depositAmount + vaultAssetsBefore, "Total assets capped at principal");
        assertLe(vault.totalAssetsWithYield(), depositAmount + vaultAssetsBefore + yieldAmount, "But yield is tracked separately");
        
        // Bob deposits same amount - should get same shares (1:1 ratio preserved)
        vm.startPrank(bob);
        asset.approve(address(vault), depositAmount);
        uint256 bobShares = vault.deposit(depositAmount, bob);
        vm.stopPrank();
        
        assertEq(bobShares, depositAmount, "Bob gets 1:1 shares despite yield");
    }
    
    function test_multipleUsers_withdrawOnlyPrincipal() public {
        // Alice deposits 10k
        vm.startPrank(alice);
        asset.approve(address(vault), 10_000e18);
        uint256 aliceShares = vault.deposit(10_000e18, alice);
        vm.stopPrank();
        
        vault.rebalance();
        
        // Simulate yield
        asset.mint(address(yieldSource), 3_000e18);
        
        // Bob deposits 5k
        vm.startPrank(bob);
        asset.approve(address(vault), 5_000e18);
        uint256 bobShares = vault.deposit(5_000e18, bob);
        vm.stopPrank();
        
        // More yield
        asset.mint(address(yieldSource), 2_000e18);
        
        // Alice withdraws all
        vm.prank(alice);
        uint256 aliceReceived = vault.redeem(aliceShares, alice, alice);
        
        // Bob withdraws all
        vm.prank(bob);
        uint256 bobReceived = vault.redeem(bobShares, bob, bob);
        
        assertEq(aliceReceived, 10_000e18, "Alice gets exactly principal");
        assertEq(bobReceived, 5_000e18, "Bob gets exactly principal");
        
        // Yield should remain
        assertGt(vault.totalAssetsWithYield(), 0, "Yield still in system");
    }
    
    // ═══════════════════════════ Yield Claiming Tests ═══════════════════════════
    
    function test_claimYield_success() public {
        uint256 depositAmount = 10_000e18;
        
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();
        
        vault.rebalance();
        
        // Simulate 30% yield
        uint256 yieldAmount = 3_000e18;
        asset.mint(address(yieldSource), yieldAmount);
        
        // Claim 2000 of the yield
        uint256 claimAmount = 2_000e18;
        uint256 treasuryBefore = asset.balanceOf(treasury);

        vm.expectEmit(true, true, true, true);
        emit IPrincipalOnlyVault.YieldClaimed(claimAmount, treasury);
        vault.claimYield(claimAmount);

        assertEq(asset.balanceOf(treasury), treasuryBefore + claimAmount, "Treasury received yield");
        
        // Vault should still be solvent
        assertGe(vault.totalAssetsWithYield(), vault.principalDeposited(), "Still solvent after claim");
    }
    
    function test_claimYield_revertsIfInsolvency() public {
        uint256 depositAmount = 10_000e18;
        
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();
        
        vault.rebalance();

        // Try to claim too much - should revert with NoYield
        vm.expectRevert(IPrincipalOnlyVault.NoYield.selector);
        vault.claimYield(1_000e18);
    }
    
    function test_claimYield_withPendingWithdrawals() public {
        // Scenario: yield earned, but users withdraw principal - claim should still work
        uint256 depositAmount = 10_000e18;
        
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();
        
        vault.rebalance();
        
        // Earn yield
        asset.mint(address(yieldSource), 5_000e18);
        
        // Alice withdraws half her principal
        vm.prank(alice);
        vault.redeem(shares / 2, alice, alice);
        
        // Should still be able to claim yield (up to the buffer amount)
        uint256 maxClaimable = vault.totalAssetsWithYield() - vault.principalDeposited();
        vault.claimYield(maxClaimable);
        assertEq(asset.balanceOf(treasury), maxClaimable, "Yield claimed successfully");
    }
    
    function test_withdrawFromSource_whenIdle_insufficient() public {
        uint256 depositAmount = 10_000e18;
        
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();
        
        // Rebalance: deploy most assets
        vault.rebalance();
        
        uint256 idleBefore = vault.idleAssets();
        assertLt(idleBefore, depositAmount, "Most assets deployed");
        
        // Alice withdraws full amount - should pull from yield source
        vm.prank(alice);
        vault.withdraw(depositAmount, alice, alice);
        
        assertEq(asset.balanceOf(alice), INITIAL_MINT, "Alice got full withdrawal");
    }
    
    function test_emergencyWithdraw() public {
        uint256 depositAmount = 10_000e18;
        
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();
        
        vault.rebalance();
        
        // Emergency withdraw (no solvency check)
        uint256 emergencyAmount = 5_000e18;
        
        vm.expectEmit(true, true, true, true);
        emit IPrincipalOnlyVault.EmergencyWithdrawal(emergencyAmount);
        vault.emergencyWithdraw(emergencyAmount);
        
        // Idle increased
        assertGt(vault.idleAssets(), depositAmount * BUFFER_BPS / 10000, "Assets withdrawn to idle");
    }
    
    function test_setTreasury() public {
        address newTreasury = makeAddr("newTreasury");
        
        vm.expectEmit(true, true, true, true);
        emit IPrincipalOnlyVault.TreasuryUpdated(treasury, newTreasury);
        vault.setTreasury(newTreasury);
        
        assertEq(vault.treasury(), newTreasury, "Treasury updated");
    }
    
    function test_setTargetBufferBps() public {
        uint256 newBuffer = 1000; // 10%
        
        vm.expectEmit(true, true, true, true);
        emit IPrincipalOnlyVault.TargetBufferBpsUpdated(BUFFER_BPS, newBuffer);
        vault.setTargetBufferBps(newBuffer);
        
        assertEq(vault.targetBufferBps(), newBuffer, "Buffer updated");
    }
    
    function test_changeYieldSource() public {
        MockERC4626 newSource = new MockERC4626(asset, "New Source", "NEW");
        
        uint256 depositAmount = 10_000e18;
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();
        
        vault.rebalance();
        uint256 deployedBefore = yieldSource.maxWithdraw(address(vault));
        assertGt(deployedBefore, 0, "Assets deployed to old source");
        
        vm.expectEmit(true, true, true, true);
        emit IPrincipalOnlyVault.YieldSourceChanged(IYieldSource(address(yieldSource)), IYieldSource(address(newSource)));
        vault.changeYieldSource(IYieldSource(address(newSource)), false);
        
        assertEq(address(vault.yieldSource()), address(newSource), "Source changed");
        assertEq(yieldSource.maxWithdraw(address(vault)), 0, "Old source withdrawn");
        assertGt(vault.idleAssets(), depositAmount * BUFFER_BPS / 10000, "Assets back in vault");
    }
    
    // ═══════════════════════════ Access Control Tests ═══════════════════════════
    
    function test_rebalance_onlyYieldManager() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.rebalance();
    }
    
    function test_claimYield_onlyYieldManager() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.claimYield(100e18);
    }
    
    function test_emergencyWithdraw_onlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.emergencyWithdraw(100e18);
    }
    
    function test_setTreasury_onlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setTreasury(makeAddr("newTreasury"));
    }
    
    // ═══════════════════════════ Error Tests ═══════════════════════════
    
    function test_constructor_revertsZeroTreasury() public {
        vm.expectRevert(IPrincipalOnlyVault.TreasuryZeroAddress.selector);
        new PrincipalOnlyVault(
            "Test",
            "TEST",
            asset,
            BUFFER_BPS,
            address(0), // Zero treasury
            IYieldSource(address(yieldSource))
        );
    }
    
    function test_constructor_revertsInvalidBufferBps() public {
        vm.expectRevert(IPrincipalOnlyVault.TargetBufferBpsTooHigh.selector);
        new PrincipalOnlyVault(
            "Test",
            "TEST",
            asset,
            10_000, // >= BPS
            treasury,
            IYieldSource(address(yieldSource))
        );
    }
    
    function test_setTreasury_revertsZeroAddress() public {
        vm.expectRevert(IPrincipalOnlyVault.TreasuryZeroAddress.selector);
        vault.setTreasury(address(0));
    }
    
    function test_setTargetBufferBps_revertsTooHigh() public {
        vm.expectRevert(IPrincipalOnlyVault.TargetBufferBpsTooHigh.selector);
        vault.setTargetBufferBps(10_000);
    }
}
