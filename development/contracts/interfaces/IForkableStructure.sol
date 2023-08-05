pragma solidity ^0.8.17;

interface IForkableStructure {
    function getChildren() external view returns (address, address);
}
