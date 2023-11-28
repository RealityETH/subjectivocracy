// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

import {MoneyBox} from "../mixin/MoneyBox.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

library CalculateMoneyBoxAddress {
    function _calculateMoneyBoxAddress(
        address _creator,
        bytes32 _salt,
        address _token
    ) internal pure returns (address) {
        return
            Create2.computeAddress(
                _salt,
                keccak256(
                    abi.encodePacked(
                        type(MoneyBox).creationCode,
                        abi.encode(_token)
                    )
                ),
                _creator
            );
    }
}
