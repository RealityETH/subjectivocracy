// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

import {MoneyBox} from "./MoneyBox.sol";

abstract contract MoneyBoxUser {

    function _calculateMoneyBoxAddress(address _creator, bytes32 _salt, address _token) internal pure returns (address) {

        // From:
        // https://docs.soliditylang.org/en/latest/control-structures.html#salted-contract-creations-create2
        return address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xff),
            _creator,
            _salt,
            keccak256(abi.encodePacked(
                type(MoneyBox).creationCode,
                abi.encode(_token) 
            ))
        )))));

    }

}
