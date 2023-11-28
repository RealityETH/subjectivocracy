// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

import {CalculateMoneyBoxAddress} from "../../contracts/lib/CalculateMoneyBoxAddress.sol";

contract ExampleMoneyBoxUser {

    function calculateMoneyBoxAddress(address _creator, bytes32 _salt, address _token) external pure returns (address) {
        return CalculateMoneyBoxAddress._calculateMoneyBoxAddress(_creator, _salt, _token);
    }

}
