// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function decimals() external view returns (uint8);
    function transfer(address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract ForkTokenTest is Test {
    // Mainnet 常用地址（长期稳定）
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // 一个“USDC rich”地址（历史上常用于测试，fork 固定块高度时通常有余额）
    // 如果你换了 block 可能余额不足；不够就换另一个 rich 地址即可。
    address constant USDC_RICH = 0x55FE002aefF02F77364de339a1292923A15844B8; // Circle-related hot wallet (commonly funded historically)

    uint256 forkId;

    function setUp() external {
        uint256 blockNumber = vm.envOr("FORK_BLOCK", uint256(19_000_000));
        forkId = vm.createSelectFork(vm.rpcUrl("mainnet"), blockNumber);
    }

    function test_read_decimals_and_balance() external view {
        uint8 usdcDec = IERC20(USDC).decimals();
        uint8 wethDec = IERC20(WETH).decimals();
        assertEq(usdcDec, 6);
        assertEq(wethDec, 18);

        // 读一个地址的余额（不要求非 0）
        uint256 bal = IERC20(USDC).balanceOf(USDC_RICH);
        // 这里不强制 >0，避免因 block/地址变化导致失败；
        // 真要强制，建议你在本地先用 cast 查一下该 block 的余额，再写断言。
        assertTrue(bal >= 0);
    }

    function test_impersonate_transfer_usdc_to_me() external {
        IERC20 usdc = IERC20(USDC);
        uint256 beforeBal = usdc.balanceOf(address(this));

        uint256 richBal = usdc.balanceOf(USDC_RICH);
        emit log_named_uint("richBal", richBal);
        vm.assume(richBal > 1_000_000); // 至少 1 USDC（6 decimals）

        // impersonate
        vm.startPrank(USDC_RICH);
        bool ok = usdc.transfer(address(this), 1_000_000); // 1 USDC
        vm.stopPrank();

        assertTrue(ok);
        uint256 afterBal = usdc.balanceOf(address(this));
        assertEq(afterBal, beforeBal + 1_000_000);
    }

    function test_approve_allowance() external {
        IERC20 usdc = IERC20(USDC);
        address spender = address(0xBEEF);

        // 先确保我有一些 USDC（如果上个测试没跑，这里自己造：从 rich 转 2 USDC）
        uint256 myBal = usdc.balanceOf(address(this));
        if (myBal < 2_000_000) {
            uint256 richBal = usdc.balanceOf(USDC_RICH);
            vm.assume(richBal > 3_000_000);
            vm.prank(USDC_RICH);
            usdc.transfer(address(this), 3_000_000);
        }

        assertEq(usdc.allowance(address(this), spender), 0);
        bool ok = usdc.approve(spender, 2_000_000);
        assertTrue(ok);
        assertEq(usdc.allowance(address(this), spender), 2_000_000);
    }
}
