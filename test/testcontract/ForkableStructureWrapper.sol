pragma solidity ^0.8.20;

import {ForkableStructure} from "../../development/contracts/mixin/ForkableStructure.sol";

contract ForkableStructureWrapper is ForkableStructure {
    function initialize(
        address _forkmanager,
        address _parentContract
    ) public override initializer {
        ForkableStructure.initialize(_forkmanager, _parentContract);
    }

    function createChildren(
        address implementation
    ) public returns (address, address) {
        return ForkableStructure._createChildren(implementation);
    }

    function setChild(uint256 index, address child) public {
        children[index] = child;
    }
}
