pragma solidity ^0.8.20;

import {ForkableStructure} from "../../contracts/mixin/ForkableStructure.sol";

contract ForkableStructureWrapper is ForkableStructure {
    function initialize(
        address _forkmanager,
        address _parentContract
    ) public override initializer {
        ForkableStructure.initialize(_forkmanager, _parentContract);
    }

    function createChildren() public returns (address, address) {
        return ForkableStructure._createChildren();
    }

    function setChild(uint256 index, address child) public {
        children[index] = child;
    }
}
