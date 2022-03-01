// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.10;

import './IAMB.sol';

contract AMB is IAMB {

    event LogPassMessage(address _contract, uint256 _gas, bytes _data);

    address sender;
    bytes32 sourceChainId;
    bytes32 public messageId;

    function requireToPassMessage(
        address _contract,
        bytes memory _data,
        uint256 _gas
    ) external returns (bytes32) {
        emit LogPassMessage(_contract, _gas, _data);

        // For our dummy implementation we return the hash of the params as an ID. No idea if this is safe for however this is used.
        return keccak256(abi.encodePacked(_contract, _gas, _data, block.number));
    }

    function maxGasPerTx() public view returns (uint256) {

    }

    function messageSender() public view returns (address) {
        return sender;
    }

    function messageSourceChainId() public view returns (bytes32) {
        return sourceChainId;
    }

    // Stripped-down simulated message passing, from:
    // https://github.com/poanetwork/tokenbridge-contracts/blob/c9377114f7bcf04cd12a30d9eca0a63362dcaedc/contracts/upgradeable_contracts/arbitrary_message/MessageProcessor.sol#L211

    /**
    * @dev Makes a call to the message executor.
    * @param _sender sender address on the other side.
    * @param _contract address of an executor contract.
    * @param _data calldata for a call to executor.
    * @param _gas gas limit for a call to executor. 2^32 - 1, if caller will pass all available gas for the execution.
    * @param _messageId id of the processed message.
    * @param _sourceChainId source chain id is of the received message.
    */
    function passMessage(
        address _sender,
        address _contract,
        bytes memory _data,
        uint256 _gas,
        bytes32 _messageId,
        bytes32 _sourceChainId
    ) external returns (bool) {
        sender = _sender;
        messageId = _messageId;
        sourceChainId = _sourceChainId;

        // After EIP-150, max gas cost allowed to be passed to the internal call is equal to the 63/64 of total gas left.
        // In reality, min(gasLimit, 63/64 * gasleft()) will be used as the call gas limit.
        // Imagine a situation, when message requires 10000000 gas to be executed successfully.
        // Also suppose, that at this point, gasleft() is equal to 10158000, so the callee will receive ~ 10158000 * 63 / 64 = 9999300 gas.
        // That amount of gas is not enough, so the call will fail. At the same time,
        // even if the callee failed the bridge contract still has ~ 158000 gas to
        // finish its execution and it will be enough. The internal call fails but
        // only because the oracle provides incorrect gas limit for the transaction
        // This check is needed here in order to force contract to pass exactly the requested amount of gas.
        // Avoiding it may lead to the unwanted message failure in some extreme cases.
        require(_gas == 0xffffffff || (gasleft() * 63) / 64 > _gas);

        (bool status, ) = _contract.call{gas: _gas}(_data);
        // _validateExecutionStatus(status);

        sender = address(0);
        messageId = bytes32(0x0);
        sourceChainId = 0;
        return status;
    }

}
