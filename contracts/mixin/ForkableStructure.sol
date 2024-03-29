// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {IForkableStructure} from "../interfaces/IForkableStructure.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {CreateChildren} from "../lib/CreateChildren.sol";

contract ForkableStructure is IForkableStructure, Initializable {
    // The forkmanager is the only one who can clone the instances and create children
    address public forkmanager;

    // The parent contract is the contract that was creating this contract during the most recent fork
    address public parentContract;

    // The children are the two instances that are created during the fork
    // Actually an array like this: address[] public children = new address[](2) would be the natural fit,
    // but this would make the initialization more complex due to proxy construction.
    // children[0] stores the first child
    // children[1] stores the second child
    mapping(uint256 => address) public children;

    modifier onlyBeforeForking() {
        if (children[0] != address(0x0)) {
            revert NoChangesAfterForking();
        }
        _;
    }

    modifier onlyAfterForking() {
        if (children[0] == address(0x0)) {
            revert OnlyAfterForking();
        }
        // The following line is not needed, as both children are created
        // simultaniously
        // if (children[1] == address(0x0)) {
        //     revert OnlyAfterForking();
        // }
        _;
    }

    modifier onlyParent() {
        if (msg.sender != parentContract) {
            revert OnlyParentIsAllowed();
        }
        _;
    }

    modifier onlyForkManger() {
        if (msg.sender != forkmanager) {
            revert OnlyForkManagerIsAllowed();
        }
        _;
    }

    /**
     * @dev Initializes the contract
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
     */
    function _createChildren()
        internal
        returns (address child0, address child1)
    {
        (child0, child1) = CreateChildren.createChildren();
        children[0] = child0;
        children[1] = child1;
    }

    function getChildren() public view returns (address, address) {
        return (children[0], children[1]);
    }
}
