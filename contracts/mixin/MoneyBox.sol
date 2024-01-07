// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

/* 
   Contract to hold funds for the duration of an asset bridge -> send
*/

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MoneyBox {
    constructor(address _token) {
        IERC20(_token).approve(msg.sender, type(uint256).max);
    }
}
