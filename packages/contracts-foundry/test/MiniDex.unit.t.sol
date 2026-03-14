// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MiniDex.sol";

contract MiniDexUnitTest is Test {
    MiniDex dex;
    address alice = address(0xA11CE);
    address bob   = address(0xB0B);

    function setUp() external {
        dex = new MiniDex(10); // 0.10%
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    // 验证存储和取出对帐正确
    function test_deposit_withdraw() external {
        vm.prank(alice);
        dex.deposit{value: 5 ether}();
        assertEq(dex.balanceEth(alice), 5 ether);

        vm.prank(alice);
        dex.withdraw(2 ether);
        assertEq(dex.balanceEth(alice), 3 ether);
        assertEq(alice.balance, 97 ether); // started 100, deposited 5, withdrew 2 => 97
    }

    // 验证下单后剩余额正确，取消订单后alice账户余额正确
    function test_place_buy_reserves_funds_and_cancel_refunds() external {
        vm.prank(alice);
        dex.deposit{value: 10 ether}();

        vm.prank(alice);
        uint256 id = dex.placeOrder(MiniDex.Side.BUY, 2, 3 ether); // quote=6e18, fee=0.001*6e18=6e15
        uint256 fee = (6 ether * 10) / 10_000; // 0.006 ether
        assertEq(dex.balanceEth(alice), 10 ether - (6 ether + fee));

        vm.prank(alice);
        dex.cancelOrder(id);
        assertEq(dex.balanceEth(alice), 10 ether);
    }

    // 验证撮合成功后alice和bob余额正确
    function test_match_buy_sell_happy_path() external {
        // Alice buyer
        vm.prank(alice);
        dex.deposit{value: 20 ether}();
        // Bob seller
        vm.prank(bob);
        dex.deposit{value: 1 ether}(); // seller doesn't need much; seller receives proceeds into dex balance

        vm.prank(alice);
        uint256 buyId = dex.placeOrder(MiniDex.Side.BUY, 2, 5 ether); // willing to pay 5 per unit
        vm.prank(bob);
        uint256 sellId = dex.placeOrder(MiniDex.Side.SELL, 2, 4 ether); // asks 4 per unit

        dex.matchOrders(buyId, sellId);

        // Bob should receive quotePaid = 2*4 = 8 ether in dex balance
        assertEq(dex.balanceEth(bob), 1 ether + 8 ether);

        // Alice actual cost = 8 ether + fee(8 ether)=0.008 ether
        uint256 feePaid = (8 ether * 10) / 10_000; // 0.008
        // Alice deposited 20; she reserved at buy price: 2*5=10 fee=0.01 => 10.01 locked then settled/refunded
        // Final balance = 20 - (8 + 0.008) = 11.992
        assertEq(dex.balanceEth(alice), 20 ether - (8 ether + feePaid));
    }
    // 验证buyprice < sellprice时会revert
    function test_match_reverts_if_price_not_crossed() external {
        vm.prank(alice);
        dex.deposit{value: 10 ether}();
        vm.prank(bob);
        dex.deposit{value: 1 ether}();

        vm.prank(alice);
        uint256 buyId = dex.placeOrder(MiniDex.Side.BUY, 1, 3 ether);
        vm.prank(bob);
        uint256 sellId = dex.placeOrder(MiniDex.Side.SELL, 1, 4 ether);

        vm.expectRevert(MiniDex.PriceNotCrossed.selector);
        dex.matchOrders(buyId, sellId);
    }

    // 取消不是自己的订单返回错误
    function test_cancel_not_owner_reverts() external {
        vm.prank(alice);
        dex.deposit{value: 10 ether}();
        vm.prank(alice);
        uint256 id = dex.placeOrder(MiniDex.Side.BUY, 1, 3 ether);

        vm.prank(bob);
        vm.expectRevert(MiniDex.NotOwner.selector);
        dex.cancelOrder(id);
    }
}