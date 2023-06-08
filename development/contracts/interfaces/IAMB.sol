// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.10;

interface IAMB {
    function requireToPassMessage(
        address _contract,
        bytes memory _data,
        uint256 _gas
    ) external returns (bytes32);

    function maxGasPerTx() external view returns (uint256);

    function messageSender() external view returns (address);

    function messageSourceChainId() external view returns (bytes32);

    function messageId() external view returns (bytes32);
}
