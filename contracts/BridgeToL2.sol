// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.6;

import './IAMB.sol';

contract BridgeToL2 is IAMB {

    address parent;

    // Arbitrary special address that will identify the forkmanager
    // This makes it look to the WhitelistArbitrator like the ForkManager never changed
    address constant FORK_MANAGER_SPECIAL_ADDRESS = 0x00000000000000000000000000000000f0f0F0F0;

    function setParent(address _fm) 
    public {
        require(parent == address(0), "Parent already initialized");
        parent = _fm;
    }

    // Any initialization steps the contract needs other than the parent address go here
    // This may include cloning other contracts
    // If necessary it can call back to the parent to get the address of the bridge it was forked from
    function init()
    external {
    }

    function requireToPassMessage(
        address, // _contract,
        bytes memory, // _data,
        uint256 // _gas
    ) override external returns (bytes32) {
        address sender = msg.sender;
        if (sender == parent) {
            sender = FORK_MANAGER_SPECIAL_ADDRESS;
        }
        // Do standard message passing

        // Guess this should be an ID?
        return bytes32(0x0);
    }


    function maxGasPerTx() override external view returns (uint256) {
    }

    function messageSender() override external view returns (address) {
    }

    function messageSourceChainId() override external view returns (bytes32) {
    }

    function messageId() override external view returns (bytes32) {
    }

}
