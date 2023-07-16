pragma solidity ^0.8.17;

import {ForkableStructure} from "../../development/contracts/mixin/ForkableStructure.sol";

contract ForkableStructureWrapper is ForkableStructure {
    function initialize(
        address _forkmanager,
        address _parentContract
    ) public override initializer {
        ForkableStructure.initialize(_forkmanager, _parentContract);
    }

    function setChild(uint256 index, address child) public {
        children[index] = child;
    }
}
