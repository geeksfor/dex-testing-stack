// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice A minimal "orderbook-style" DEX demo for testing practice.
/// - Users deposit ETH as collateral
/// - Place BUY/SELL limit orders (price in wei per 1 base unit; base is abstract integer amount)
/// - Simple matcher matches one BUY and one SELL if buyPrice >= sellPrice
/// - Fee charged on quote (ETH) from buyer side: feeBps (basis points)
/// This is intentionally simplified for QA/test framework demos.
contract MiniDex {
    enum Side {
        BUY,
        SELL
    }

    struct Order {
        address owner; // 下单的人
        Side side; // BUY or SELL
        uint96 amount; // base amount
        uint128 price; // quote per base
        bool active; // 是否有效（没取消、没完全成交）
    }

    uint256 public nextOrderId = 1; // 自增订单号，从 1 开始
    uint16 public immutable feeBps; // e.g. 10 = 0.10%

    mapping(address => uint256) public balanceEth; // 用户在合约中的 可用 ETH 余额
    mapping(uint256 => Order) public orders; // 订单簿（但没有价格档位/队列等结构，只有存订单）

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    event OrderPlaced(uint256 indexed orderId, address indexed owner, Side side, uint96 amount, uint128 price);
    event OrderCancelled(uint256 indexed orderId, address indexed owner);

    event Matched(
        uint256 indexed buyOrderId,
        uint256 indexed sellOrderId,
        address indexed buyer,
        address seller,
        uint96 amount,
        uint128 execPrice,
        uint256 quotePaid,
        uint256 feePaid
    );

    error ZeroAmount();
    error InsufficientBalance();
    error NotOwner();
    error InactiveOrder();
    error SideMismatch(); // 买卖方向不匹配
    error PriceNotCrossed(); // 买价小于卖价，不能撮合

    constructor(uint16 _feeBps) {
        require(_feeBps <= 1000, "fee too high"); // <=10%
        feeBps = _feeBps;
    }

    // ---------- Funds ----------
    // 用户存eth
    function deposit() external payable {
        if (msg.value == 0) revert ZeroAmount();
        balanceEth[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        uint256 bal = balanceEth[msg.sender];
        if (bal < amount) revert InsufficientBalance();
        // 因为在 Solidity 0.8+ 里，
        // 所有 + - * 默认都会做“溢出/下溢检查”。这个检查会多生成一些 EVM 指令（比较、条件跳转、revert 逻辑），所以会多花 gas
        unchecked {
            balanceEth[msg.sender] = bal - amount;
        }
        // ("") 是 call 的 calldata，空字符串表示不调用函数、只转 ETH；不能省略，但可以用 new bytes(0) 等价替代。
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");
        emit Withdraw(msg.sender, amount);
    }

    // ---------- Orders ----------
    function placeOrder(Side side, uint96 amount, uint128 price) external returns (uint256 orderId) {
        if (amount == 0 || price == 0) revert ZeroAmount();

        // Reserve funds for BUY: amount * price (+fee worst-case) must be <= balance
        if (side == Side.BUY) {
            uint256 quote = uint256(amount) * uint256(price);
            uint256 fee = (quote * feeBps) / 10_000;
            uint256 need = quote + fee;
            if (balanceEth[msg.sender] < need) revert InsufficientBalance();
            // Reserve by subtracting immediately (simple approach)
            balanceEth[msg.sender] -= need;
        }

        orderId = nextOrderId++;
        orders[orderId] = Order({owner: msg.sender, side: side, amount: amount, price: price, active: true});

        emit OrderPlaced(orderId, msg.sender, side, amount, price);
    }

    function cancelOrder(uint256 orderId) external {
        // 为什么加storage？
        // storage：链上持久化数据的“引用”（读写都行），省拷贝
        Order storage o = orders[orderId];
        if (!o.active) revert InactiveOrder();
        if (o.owner != msg.sender) revert NotOwner();

        o.active = false;

        // Refund reserved funds if BUY
        if (o.side == Side.BUY) {
            uint256 quote = uint256(o.amount) * uint256(o.price);
            uint256 fee = (quote * feeBps) / 10_000;
            balanceEth[msg.sender] += (quote + fee);
        }

        emit OrderCancelled(orderId, msg.sender);
    }

    /// @notice Match exactly one buy + one sell order for min(buy.amount, sell.amount)
    /// Execution price is sell.price (maker ask). Fee charged from buyer on quote.
    function matchOrders(uint256 buyOrderId, uint256 sellOrderId) external {
        Order storage b = orders[buyOrderId];
        Order storage s = orders[sellOrderId];

        if (!b.active || !s.active) revert InactiveOrder();
        if (b.side != Side.BUY || s.side != Side.SELL) revert SideMismatch();
        if (b.price < s.price) revert PriceNotCrossed();

        uint96 matchAmt = b.amount <= s.amount ? b.amount : s.amount;
        if (matchAmt == 0) revert ZeroAmount();

        uint128 execPrice = s.price;
        uint256 quotePaid = uint256(matchAmt) * uint256(execPrice);
        uint256 feePaid = (quotePaid * feeBps) / 10_000;

        // Seller receives quotePaid (ETH) from contract, buyer already reserved (buy reserved at b.price).
        // We refund buyer the "unused" part from reservation:
        // reserved = matchAmt*b.price + fee(matchAmt*b.price)  (but we reserved on original amount; simplified below)
        // For simplicity: refund based on matched portion at buy.price, then charge actual at sell.price.
        // Net effect: buyer pays quotePaid + feePaid, plus potential "spread refund" if b.price > execPrice.

        // Compute buyer reserved for matched portion (at buy.price)
        uint256 buyerReservedQuote = uint256(matchAmt) * uint256(b.price);
        uint256 buyerReservedFee = (buyerReservedQuote * feeBps) / 10_000;
        uint256 buyerReservedTotal = buyerReservedQuote + buyerReservedFee;

        uint256 buyerActualTotal = quotePaid + feePaid;

        if (buyerReservedTotal >= buyerActualTotal) {
            // refund extra to buyer balance
            balanceEth[b.owner] += (buyerReservedTotal - buyerActualTotal);
        } else {
            // This shouldn't happen if sell.price <= buy.price, but fee rounding could cause 1-wei mismatch
            // To keep demo strict, revert to surface rounding issues in tests.
            revert InsufficientBalance();
        }

        // Pay seller
        balanceEth[s.owner] += quotePaid;

        // Update remaining amounts; deactivate if filled
        b.amount -= matchAmt;
        s.amount -= matchAmt;

        if (b.amount == 0) b.active = false;
        if (s.amount == 0) s.active = false;

        emit Matched(buyOrderId, sellOrderId, b.owner, s.owner, matchAmt, execPrice, quotePaid, feePaid);
    }

    /// @notice Helper: sum of reserved buyer funds currently locked in active BUY orders
    /// This is only used by tests/invariants for accounting sanity.
    function lockedInBuyOrders() external view returns (uint256 locked) {
        // This is O(n). Fine for demo tests.
        for (uint256 i = 1; i < nextOrderId; i++) {
            Order storage o = orders[i];
            if (o.active && o.side == Side.BUY) {
                uint256 q = uint256(o.amount) * uint256(o.price);
                uint256 f = (q * feeBps) / 10_000;
                locked += (q + f);
            }
        }
    }

    receive() external payable {
        revert("use deposit()");
    }
}
