// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MiniDex.sol";

contract MiniDexFuzzTest is Test {
    MiniDex dex;
    address alice = address(0xA11CE);

    function setUp() external {
        dex = new MiniDex(10); // 0.10%
        vm.deal(alice, 10_000 ether);
    }

    function testFuzz_placeBuy_then_cancel_refunds(uint96 amount, uint128 price) external {
      // constrain
      amount = uint96(bound(amount, 1, 1_000));
      price  = uint128(bound(price, 1e9, 10 ether)); // avoid overflow, keep realistic

      vm.startPrank(alice);
      dex.deposit{value: 1000 ether}();

      uint256 quote = uint256(amount) * uint256(price);
      uint256 fee   = (quote * dex.feeBps()) / 10_000;
      uint256 need  = quote + fee;

      vm.assume(need <= dex.balanceEth(alice)); // ensure can place
      uint256 beforeBal = dex.balanceEth(alice);

      uint256 id = dex.placeOrder(MiniDex.Side.BUY, amount, price);
      uint256 afterPlace = dex.balanceEth(alice);
      assertEq(afterPlace, beforeBal - need);

      dex.cancelOrder(id);
      uint256 afterCancel = dex.balanceEth(alice);
      assertEq(afterCancel, beforeBal);
      vm.stopPrank();
    }

    function testFuzz_match_never_increases_totalAssets(uint96 amt, uint128 buyPrice, uint128 sellPrice) external {
      // Here we assert a high-level property: matching redistributes balances but doesn't mint ETH.
      // (In this demo, all value stays within balanceEth accounting)
      amt = uint96(bound(amt, 1, 100));
      buyPrice = uint128(bound(buyPrice, 1e9, 10 ether));
      sellPrice = uint128(bound(sellPrice, 1e9, buyPrice)); // ensure crossed

      address buyer = address(0xBEEF);
      address seller = address(0xCAFE);
      vm.deal(buyer, 10_000 ether);
      vm.deal(seller, 10_000 ether);

      vm.prank(buyer);
      dex.deposit{value: 1000 ether}();
      vm.prank(seller);
      dex.deposit{value: 1 ether}();

      uint256 totalBefore = dex.balanceEth(buyer) + dex.balanceEth(seller);

      vm.prank(buyer);
      uint256 buyId = dex.placeOrder(MiniDex.Side.BUY, amt, buyPrice);
      vm.prank(seller);
      uint256 sellId = dex.placeOrder(MiniDex.Side.SELL, amt, sellPrice);

      dex.matchOrders(buyId, sellId);

      uint256 totalAfter = dex.balanceEth(buyer) + dex.balanceEth(seller);

      // Total should be unchanged (since fee stays inside buyer deduction; we didn't model fee recipient; it remains "burned" within accounting).
      // In this simplified model, fee is not transferred anywhere; it's just not credited back, so totalAfter <= totalBefore.
      assertLe(totalAfter, totalBefore);
    }
}