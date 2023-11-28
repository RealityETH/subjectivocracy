// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

import {MoneyBoxUser} from "../../contracts/MoneyBoxUser.sol";

contract ExampleMoneyBoxUser is MoneyBoxUser {

    function calculateMoneyBoxAddress(address _creator, bytes32 _salt, address _token) external pure returns (address) {
        return _calculateMoneyBoxAddress(_creator, _salt, _token);
    }

}
