// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice A toy share vault with rounding bug:
/// - shares minted = assets * totalShares / totalAssets (floor)
/// - If totalAssets is huge and deposit is tiny, minted shares may be 0 (user loses assets)
contract ShareVaultRoundingVuln {
    uint256 public totalAssets;
    uint256 public totalShares;
    mapping(address => uint256) public sharesOf;

    event Deposit(address indexed user, uint256 assets, uint256 sharesMinted);
    event Withdraw(address indexed user, uint256 assetsOut, uint256 sharesBurned);

    function deposit(uint256 assets) external {
        require(assets > 0, "zero");
        uint256 shares;
        if (totalShares == 0) {
            // bootstrap 1:1
            shares = assets;
        } else {
            // FLOOR rounding
            shares = (assets * totalShares) / totalAssets;
        }

        // VULN: allow shares == 0, user donates assets to vault
        totalAssets += assets;
        totalShares += shares;
        sharesOf[msg.sender] += shares;

        emit Deposit(msg.sender, assets, shares);
    }

    function withdraw(uint256 shares) external returns (uint256 assetsOut) {
        require(shares > 0, "zero");
        require(sharesOf[msg.sender] >= shares, "insufficient");

        // FLOOR rounding on assets out as well (typical)
        assetsOut = (shares * totalAssets) / totalShares;

        sharesOf[msg.sender] -= shares;
        totalShares -= shares;
        totalAssets -= assetsOut;

        emit Withdraw(msg.sender, assetsOut, shares);
    }
}
