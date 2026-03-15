// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Vulnerable vault: withdraw sends ETH before updating balance (classic reentrancy)
contract ReentrancyVaultVuln {
    mapping(address => uint256) public balanceOf;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    function deposit() external payable {
        require(msg.value > 0, "zero");
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "zero");
        require(balanceOf[msg.sender] >= amount, "insufficient");

        // VULN: external call before state update
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "send failed");

        unchecked {
            balanceOf[msg.sender] -= amount;
        }
        emit Withdraw(msg.sender, amount);
    }

    receive() external payable {}
}
