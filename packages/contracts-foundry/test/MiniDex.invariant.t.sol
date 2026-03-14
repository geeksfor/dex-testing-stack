// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../src/MiniDex.sol";

contract MiniDexHandler is Test {
    MiniDex public dex;
    address[] public users;

    constructor(MiniDex _dex, address[] memory _users) {
        dex = _dex;
        users = _users;
        for (uint256 i = 0; i < users.length; i++) {
            vm.deal(users[i], 10_000 ether);
        }
    }

    function deposit(uint256 userIndex, uint256 amount) external {
        address u = users[userIndex % users.length];
        amount = bound(amount, 1e9, 5 ether);
        vm.prank(u);
        dex.deposit{value: amount}();
    }

    function withdraw(uint256 userIndex, uint256 amount) external {
        address u = users[userIndex % users.length];
        uint256 bal = dex.balanceEth(u);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        vm.prank(u);
        dex.withdraw(amount);
    }

    function placeBuy(uint256 userIndex, uint96 amt, uint128 price) external {
        address u = users[userIndex % users.length];
        amt = uint96(bound(amt, 1, 50));
        price = uint128(bound(price, 1e9, 5 ether));

        uint256 quote = uint256(amt) * uint256(price);
        uint256 fee = (quote * dex.feeBps()) / 10_000;
        uint256 need = quote + fee;

        if (dex.balanceEth(u) < need) return;

        vm.prank(u);
        dex.placeOrder(MiniDex.Side.BUY, amt, price);
    }

    function placeSell(uint256 userIndex, uint96 amt, uint128 price) external {
        address u = users[userIndex % users.length];
        amt = uint96(bound(amt, 1, 50));
        price = uint128(bound(price, 1e9, 5 ether));
        vm.prank(u);
        dex.placeOrder(MiniDex.Side.SELL, amt, price);
    }

    function cancel(uint256 orderId, uint256 userIndex) external {
        address u = users[userIndex % users.length];
        // may revert if not owner/inactive; ignore by try/catch
        vm.prank(u);
        try dex.cancelOrder(orderId) {} catch {}
    }

    function matchOne(uint256 buyId, uint256 sellId) external {
        // may revert due to constraints; ignore
        try dex.matchOrders(buyId, sellId) {} catch {}
    }

    function sumUserBalances() external view returns (uint256 s) {
        for (uint256 i = 0; i < users.length; i++) {
            s += dex.balanceEth(users[i]);
        }
    }
}

contract MiniDexInvariantTest is StdInvariant, Test {
    MiniDex dex;
    MiniDexHandler handler;

    function setUp() external {
        dex = new MiniDex(10);
        address[] memory users = new address[](3);
        users[0] = address(0x1111);
        users[1] = address(0x2222);
        users[2] = address(0x3333);

        handler = new MiniDexHandler(dex, users);

        targetContract(address(handler));
    }

    /// Invariant: contract ETH == sum(user balances) + locked in active BUY orders
    function invariant_eth_accounting_consistent() external view {
        uint256 contractEth = address(dex).balance;
        uint256 sumBalances = handler.sumUserBalances();
        uint256 locked = dex.lockedInBuyOrders();
        assertEq(contractEth, sumBalances + locked);
    }
}
