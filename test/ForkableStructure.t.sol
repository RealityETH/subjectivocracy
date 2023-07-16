pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {ForkableStructureWrapper} from "./testcontract/ForkableStructureWrapper.sol";

contract ForkStructureTest is Test {
    ForkableStructureWrapper public forkStructure;

    address public forkmanager = address(0x123);
    address public parentContract = address(0x456);
    address public child1 = address(0x789);
    address public child2 = address(0xabc);

    function setUp() public {
        forkStructure = new ForkableStructureWrapper();
        forkStructure.initialize(forkmanager, parentContract);
        // assume the contract has a setChild function
        forkStructure.setChild(0, child1);
        forkStructure.setChild(1, child2);
    }

    function testInitialize() public {
        assertEq(forkStructure.forkmanager(), forkmanager);
        assertEq(forkStructure.parentContract(), parentContract);
    }

    function testGetChild() public {
        assertEq(forkStructure.getChild(0), child1);
        assertEq(forkStructure.getChild(1), child2);
    }

    function testGetChildren() public {
        (address returnedChild1, address returnedChild2) = forkStructure
            .getChildren();
        assertEq(returnedChild1, child1);
        assertEq(returnedChild2, child2);
    }
}
