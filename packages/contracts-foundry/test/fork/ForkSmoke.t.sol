// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

contract ForkSmokeTest is Test {
    uint256 forkId;

    function setUp() external {
        // 你也可以用 env 指定 block：FORK_BLOCK=19000000 之类
        uint256 blockNumber = vm.envOr("FORK_BLOCK", uint256(19_000_000));

        // 使用 foundry.toml 的 rpc_endpoints.mainnet
        forkId = vm.createSelectFork(vm.rpcUrl("mainnet"), blockNumber);
    }

    function test_fork_is_at_expected_block() external {
        assertEq(block.number, vm.envOr("FORK_BLOCK", uint256(19_000_000)));
        // 读一下 basefee / chainid 之类，确保 fork 正常
        assertEq(block.chainid, 1);
        assertGt(block.basefee, 0);
    }

    function test_can_read_latest_blockhash() external view {
        // fork 下能正常读 blockhash（注意只能读最近 256 个区块）
        bytes32 h = blockhash(block.number - 1);
        assertTrue(h != bytes32(0));
    }
}
