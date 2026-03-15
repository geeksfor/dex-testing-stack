// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract ShareVaultRoundingFixed {
    uint256 public totalAssets;
    uint256 public totalShares;
    mapping(address => uint256) public sharesOf;

    event Deposit(address indexed user, uint256 assets, uint256 sharesMinted);
    event Withdraw(address indexed user, uint256 assetsOut, uint256 sharesBurned);

    function deposit(uint256 assets) external {
        require(assets > 0, "zero");
        uint256 shares;
        if (totalShares == 0) {
            shares = assets;
        } else {
            shares = (assets * totalShares) / totalAssets;
        }

        require(shares > 0, "dust deposit"); // FIX: no free donation

        totalAssets += assets;
        totalShares += shares;
        sharesOf[msg.sender] += shares;

        emit Deposit(msg.sender, assets, shares);
    }

    function withdraw(uint256 shares) external returns (uint256 assetsOut) {
        require(shares > 0, "zero");
        require(sharesOf[msg.sender] >= shares, "insufficient");

        assetsOut = (shares * totalAssets) / totalShares;

        sharesOf[msg.sender] -= shares;
        totalShares -= shares;
        totalAssets -= assetsOut;

        emit Withdraw(msg.sender, assetsOut, shares);
    }
}
