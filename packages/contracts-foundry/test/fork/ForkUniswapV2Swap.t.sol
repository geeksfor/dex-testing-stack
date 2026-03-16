// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract ForkUniswapV2SwapTest is Test {
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Uniswap V2 Router02 mainnet
    address constant UNI_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    uint256 forkId;

    function setUp() external {
        uint256 blockNumber = vm.envOr("FORK_BLOCK", uint256(19_000_000));
        forkId = vm.createSelectFork(vm.rpcUrl("mainnet"), blockNumber);
    }

    function test_swap_weth_to_usdc_on_fork() external {
        // 1) 我用 ETH 包装成 WETH
        IWETH weth = IWETH(WETH);
        /**
         * 这会发生一笔 对 WETH 合约的调用（to = WETH 合约地址，value = 1 ETH）。
         *
         *   WETH 合约收到这 1 ETH 后，会给 调用者（msg.sender） 铸造/记账等量的 WETH（ERC20 余额增加）。
         *
         *   在 Foundry 测试里，msg.sender 默认就是 你的测试合约地址 address(this)，所以最终效果是：
         *
         *   WETH 合约地址 的 ETH 余额 +1 ETH
         *
         *   测试合约地址 的 WETH 余额 +1 WETH
         */
        weth.deposit{value: 1 ether}();

        // 2) approve router 花我的 WETH
        bool ok = weth.approve(UNI_V2_ROUTER, type(uint256).max);
        assertTrue(ok);

        // 3) swapExactTokensForTokens: 0.1 WETH -> USDC
        uint256 amountIn = 0.1 ether;

        // 注意：amountOutMin 在真实环境要按报价/滑点算。
        // fork demo 为了稳定：先设置成 1（允许任意输出），重点是“跑通集成链路+断言余额变化”
        uint256 amountOutMin = 1;

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;

        uint256 usdcBefore = IERC20(USDC).balanceOf(address(this));

        uint256 deadline = block.timestamp + 1 hours;
        uint256[] memory amounts = IUniswapV2Router02(UNI_V2_ROUTER)
            .swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), deadline);

        // amounts[0] == amountIn; amounts[1] == out
        assertEq(amounts[0], amountIn);

        uint256 usdcAfter = IERC20(USDC).balanceOf(address(this));
        assertGt(usdcAfter, usdcBefore);

        // 额外：至少拿到一点 USDC（6 decimals），避免极端情况
        assertGe(usdcAfter - usdcBefore, 1);
    }

    receive() external payable {}
}
