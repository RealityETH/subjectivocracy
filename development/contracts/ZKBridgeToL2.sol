// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity ^0.8.10;

import "./interfaces/IZKBridge.sol";

contract ZKBridgeToL2 {
    address public parent;

    // Arbitrary special address that will identify the forkmanager
    // This makes it look to the WhitelistArbitrator like the ForkManager never changed
    address public constant FORK_MANAGER_SPECIAL_ADDRESS =
        0x00000000000000000000000000000000f0f0F0F0;

    // Borrowed from AMB for testing
    // ZKSync doesn't currently seem to emit an event here
    event LogPassMessage(address _contract, uint256 _gas, bytes _data);

    function setParent(address _fm) public {
        require(parent == address(0), "Parent already initialized");
        parent = _fm;
    }

    // Any initialization steps the contract needs other than the parent address go here
    // This may include cloning other contracts
    // If necessary it can call back to the parent to get the address of the bridge it was forked from
    function init() external {}

    function requestExecute(
        address _contractAddressL2,
        bytes memory _calldata,
        uint256 _ergsLimit,
        Operations.QueueType,
        Operations.OpTree
    ) external payable {
        address sender = msg.sender;
        if (sender == parent) {
            sender = FORK_MANAGER_SPECIAL_ADDRESS;
        }
        // Do standard message passing

        emit LogPassMessage(_contractAddressL2, _ergsLimit, _calldata);
    }
}
