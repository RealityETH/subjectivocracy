pragma solidity ^0.8.17;


interface IForkableStructure {
    function getChild(uint256 index) external view returns (address);
}