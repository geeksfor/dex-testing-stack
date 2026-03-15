// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/security/ApproveRaceToken.sol";

contract ApproveRaceTest is Test {
    function test_approve_race_front_run_spends_old_and_new() external {
        ApproveRaceToken t = new ApproveRaceToken();
        address alice = address(0xA);
        address spender = address(0xB);
        address attacker = spender; // spender 就是潜在攻击者

        // Give Alice 100 tokens
        t.transfer(alice, 100 ether);

        // Alice approves 10
        vm.prank(alice);
        t.approve(spender, 10 ether);

        // Alice wants to change allowance from 10 -> 20
        // Attack: spender front-runs and spends 10 before new approve lands, then spends 20 after.
        // We'll simulate tx ordering.

        // Tx1 (front-run): spender spends 10
        vm.prank(attacker);
        t.transferFrom(alice, attacker, 10 ether);

        // Tx2 (user): alice sets allowance to 20 (without setting to 0 first)
        vm.prank(alice);
        t.approve(spender, 20 ether);

        // Tx3: spender spends 20
        vm.prank(attacker);
        t.transferFrom(alice, attacker, 20 ether);

        // Total stolen = 30, which is > original intended 20
        assertEq(t.balanceOf(attacker), 30 ether);
        assertEq(t.balanceOf(alice), 70 ether);
    }

    function test_mitigation_set_to_zero_first() external {
        ApproveRaceToken t = new ApproveRaceToken();
        address alice = address(0xA);
        address spender = address(0xB);

        t.transfer(alice, 100 ether);

        vm.prank(alice);
        t.approve(spender, 10 ether);

        // Mitigation: set 0 then set new value
        vm.prank(alice);
        t.approve(spender, 0);

        vm.prank(alice);
        t.approve(spender, 20 ether);

        // Now even if spender tries to front-run between 0 and 20, the window is smaller,
        // and the safe pattern is usually combined with permit/increaseAllowance design.
        vm.prank(spender);
        t.transferFrom(alice, spender, 20 ether);

        assertEq(t.balanceOf(spender), 20 ether);
    }
}
