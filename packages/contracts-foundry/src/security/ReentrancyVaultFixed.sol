// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Fixed vault: CEI + simple reentrancy guard
contract ReentrancyVaultFixed {
    mapping(address => uint256) public balanceOf;
    uint256 private locked = 1;

    modifier nonReentrant() {
        require(locked == 1, "reentrant");
        locked = 2;
        _;
        locked = 1;
    }

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    function deposit() external payable {
        require(msg.value > 0, "zero");
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "zero");
        uint256 bal = balanceOf[msg.sender];
        require(bal >= amount, "insufficient");

        // Effects first
        balanceOf[msg.sender] = bal - amount;

        // Interaction after
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "send failed");

        emit Withdraw(msg.sender, amount);
    }
    receive() external payable {}
}
