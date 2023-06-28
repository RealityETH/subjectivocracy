// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./interfaces/IERC20Mint.sol";

contract ERC20Mint is ERC20 {
    function mint(address to, uint256 value) external {
        balanceOf[to] = balanceOf[to] + value;
    }
}
