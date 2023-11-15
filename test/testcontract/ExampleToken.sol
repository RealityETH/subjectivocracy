// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ExampleToken is ERC20 {

    constructor() ERC20("My Token", "MT") {
    }

    // Permission-free mint for testing
    function fakeMint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }

}
