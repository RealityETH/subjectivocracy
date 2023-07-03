pragma solidity ^0.8.17;

import "../interfaces/IForkableStructure.sol";

contract ForkStructure is IForkableStructure {
    address public forkmanager;
    address public parentContract;
    // actually an array would be the natural fit, but this would make the initialization more complex
    // due to proxy construction.
    // The option: address[] public children = new address[](2) would need a custom constructor
    // hence we are taking a mapping
    mapping(uint256 => address) public children;

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

    function getChildren() external view returns (address, address) {
        return (children[0], children[1]);
    }
}
