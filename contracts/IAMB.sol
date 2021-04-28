pragma solidity ^0.4.25;

interface IAMB {
    function requireToPassMessage(
        address _contract,
        bytes _data,
        uint256 _gas
    ) external returns (bytes32);

    function maxGasPerTx() external view returns (uint256);

    function messageSender() external view returns (address);

    function messageSourceChainId() external view returns (bytes32);

    function messageId() external view returns (bytes32);
}
