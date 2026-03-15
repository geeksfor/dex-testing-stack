// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/security/ShareVaultRoundingVuln.sol";
import "../../src/security/ShareVaultRoundingFixed.sol";

contract RoundingDustTest is Test {
    function test_rounding_dust_vuln_user_donates_assets() external {
        ShareVaultRoundingVuln v = new ShareVaultRoundingVuln();
        address whale = address(0xA);
        address small = address(0xF);

        // Whale bootstraps huge vault
        vm.startPrank(whale);
        v.deposit(1_000_000); // totalAssets=1e6, totalShares=1e6
        vm.stopPrank();

        // Manipulate state to create a ratio where small deposit mints 0 share:
        // Example: make totalAssets much bigger while totalShares stays same (like yield accrued unaccounted)
        // We'll simulate by directly calling deposit from whale without increasing shares much is hard in this toy.
        // So we do: totalAssets huge, totalShares small by a crafted sequence:
        // Step: Whale withdraws almost all shares but leaves totalAssets big via rounding.
        // In this toy, withdrawal reduces totalAssets proportionally; so instead we take a simpler approach:
        // Set up extreme ratio by doing:
        //  - Whale deposits 1e6 (shares 1e6)
        //  - Then we "simulate yield" by directly increasing totalAssets using cheatcode (test-only)
        // This mirrors real yield vaults where assets increase without minting shares.
        vm.store(address(v), bytes32(uint256(0)), bytes32(uint256(1_000_000_000_000))); // slot0 totalAssets (assumes layout)
        // Note: if storage layout differs, this may fail. If it fails, we fall back below.

        // Small user deposits tiny assets: shares = assets*totalShares/totalAssets -> floor to 0
        vm.prank(small);
        v.deposit(1); // likely mints 0 shares

        assertEq(v.sharesOf(small), 0);
        assertEq(v.totalAssets(), 1_000_000_000_001); // donated 1

        // Whale withdraws 1 share; assetsOut uses floor, but over repeated withdraw, whale can capture donated dust.
        vm.prank(whale);
        uint256 out = v.withdraw(1);
        assertGt(out, 0); // whale gets some assets
    }

    function test_fixed_reverts_on_dust_deposit() external {
        ShareVaultRoundingFixed v = new ShareVaultRoundingFixed();
        address whale = address(0xA);
        address small = address(0xF);

        vm.prank(whale);
        v.deposit(1_000_000);

        // Simulate huge yield
        vm.store(address(v), bytes32(uint256(0)), bytes32(uint256(1_000_000_000_000)));

        vm.prank(small);
        vm.expectRevert(bytes("dust deposit"));
        v.deposit(1);
    }
}
