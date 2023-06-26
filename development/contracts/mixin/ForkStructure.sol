pragma solidity ^0.8.17;

import "../interfaces/IForkableStructure.sol";

contract ForkStructure is IForkableStructure {
    address public forkmanager;
    address public parentContract;
    address[] public children = new address[](2);

    modifier onlyParent() {
        require(msg.sender == parentContract);
        _;
    }

    modifier onlyForkManger() {
        require(msg.sender == forkmanager);
        _;
    }

    function getChild(uint256 index) external view override returns (address) {
        return children[index];
    }
}
