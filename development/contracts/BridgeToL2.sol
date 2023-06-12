// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.10;

import "./interfaces/IAMB.sol";

contract BridgeToL2 is IAMB {
    event LogPassMessage(address _contract, uint256 _gas, bytes _data);

    address parent;

    // Arbitrary special address that will identify the forkmanager
    // This makes it look to the WhitelistArbitrator like the ForkManager never changed
    address constant FORK_MANAGER_SPECIAL_ADDRESS =
        0x00000000000000000000000000000000f0f0F0F0;

    function setParent(address _fm) public {
        require(parent == address(0), "Parent already initialized");
        parent = _fm;
    }

    // Any initialization steps the contract needs other than the parent address go here
    // This may include cloning other contracts
    // If necessary it can call back to the parent to get the address of the bridge it was forked from
    function init() external {}

    function requireToPassMessage(
        address _contract,
        bytes memory _data,
        uint256 _gas
    ) external override returns (bytes32) {
        address sender = msg.sender;
        if (sender == parent) {
            sender = FORK_MANAGER_SPECIAL_ADDRESS;
        }
        // Do standard message passing

        emit LogPassMessage(_contract, _gas, _data);

        // For our dummy implementation we return the hash of the params as an ID. No idea if this is safe for however this is used.
        return
            keccak256(abi.encodePacked(_contract, _gas, _data, block.number));
    }

    function maxGasPerTx() external view override returns (uint256) {}

    function messageSender() external view override returns (address) {}

    function messageSourceChainId() external view override returns (bytes32) {}

    function messageId() external view override returns (bytes32) {}
}
