// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.10;

import "openzeppelin/token/ERC20/IERC20.sol";

/**
 * @title ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
interface IERC20Mint is IERC20 {
    function mint(address to, uint256 value) external;
}
