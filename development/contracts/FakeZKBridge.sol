// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity ^0.8.10;

import './IZKBridge.sol';

contract FakeZKBridge {

    function requestExecute(
        address _contractAddressL2,
        bytes memory _calldata,
        uint256 _ergsLimit,
        Operations.QueueType _queueType,
        Operations.OpTree _opTree
    ) external payable {

    }

}
