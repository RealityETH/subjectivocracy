pragma solidity ^0.8.17;

import {IForkableStructure} from "../interfaces/IForkableStructure.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract ForkableStructure is IForkableStructure, Initializable {
    // The forkmanager is the only one who can clone the instances and create children
    address public forkmanager;

    // The parent contract is the contract that was holding tokens or logic before the most recent fork
    address public parentContract;

    // The children are the two instances that are created during the fork
    // Actually an array like this: address[] public children = new address[](2) would be the natural fit,
    // but this would make the initialization more complex due to proxy construction.
    mapping(uint256 => address) public children;

    function initialize(
        address _forkmanager,
        address _parentContract
    ) public virtual onlyInitializing {
        forkmanager = _forkmanager;
        parentContract = _parentContract;
    }

    modifier onlyParent() {
        require(msg.sender == parentContract, "Only available for parent");
        _;
    }

    modifier onlyForkManger() {
        require(msg.sender == forkmanager, "Only forkManager is allowed");
        _;
    }

    function getChild(uint256 index) external view returns (address) {
        return children[index];
    }

    function getChildren() external view returns (address, address) {
        return (children[0], children[1]);
    }
}
