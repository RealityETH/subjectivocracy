pragma solidity ^0.8.17;

import {IForkableStructure} from "../interfaces/IForkableStructure.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ForkableStructure} from "./ForkableStructure.sol";
import {CreateChildren} from "../lib/CreateChildren.sol";

contract ForkableStructure is IForkableStructure, Initializable {
    // The forkmanager is the only one who can clone the instances and create children
    address public forkmanager;

    // The parent contract is the contract that was holding tokens or logic before the most recent fork
    address public parentContract;

    // The children are the two instances that are created during the fork
    // Actually an array like this: address[] public children = new address[](2) would be the natural fit,
    // but this would make the initialization more complex due to proxy construction.
    mapping(uint256 => address) public children;

    modifier onlyBeforeForking() {
        require(children[0] == address(0x0), "No changes after forking");
        _;
    }

    modifier onlyAfterForking() {
        require(children[0] != address(0x0), "onlyAfterForking");
        _;
    }
    modifier onlyParent() {
        require(msg.sender == parentContract, "Only available for parent");
        _;
    }

    modifier onlyForkManger() {
        require(msg.sender == forkmanager, "Only forkManager is allowed");
        _;
    }

    /**
     * @dev Initializes the contract.
     * @param _forkmanager The address of the forkmanager contract.
     * @param _parentContract The address of the parent contract.
     */
    function initialize(
        address _forkmanager,
        address _parentContract
    ) public virtual onlyInitializing {
        forkmanager = _forkmanager;
        parentContract = _parentContract;
    }

    /**
     *  @dev Internal function to create the children contracts.
     * @param implementation Allows to pass a different implementation contract for the second proxied child.
     */
    function _createChildren(
        address implementation
    ) internal returns (address forkingManager1, address forkingManager2) {
        (forkingManager1, forkingManager2) = CreateChildren.createChildren(
            implementation
        );
        children[0] = forkingManager1;
        children[1] = forkingManager2;
    }

    function getChildren() external view returns (address, address) {
        return (children[0], children[1]);
    }
}
