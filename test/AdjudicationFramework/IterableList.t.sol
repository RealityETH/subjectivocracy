pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IterableListWrapper} from "./../testcontract/IterableListWrapper.sol";

contract IterableListTest is Test {
    IterableListWrapper public iterableList;

    address public item1 = address(0x123);
    address public item2 = address(0x456);
    address public item3 = address(0x789);

    function setUp() public {
        iterableList = new IterableListWrapper();
    }

    function testAddToList() public {
        // Initially, the list should be empty
        assertEq(iterableList.getNumberOfListMembers(), 0);

        // Add an item and check if it's in the list
        vm.prank(address(this));
        iterableList.addToList(item1);
        assertTrue(iterableList.contains(item1));

        // Check if the count is updated
        assertEq(iterableList.getNumberOfListMembers(), 1);
    }

    function testRemoveFromList() public {
        // Add two items
        vm.prank(address(this));
        iterableList.addToList(item1);
        iterableList.addToList(item2);

        // Remove one item
        vm.prank(address(this));
        iterableList.removeFromList(item1);
        assertFalse(iterableList.contains(item1));

        // Check if the count is updated
        assertEq(iterableList.getNumberOfListMembers(), 1);
    }

    function testGetAllListMembers() public {
        // Add some items
        vm.prank(address(this));
        iterableList.addToList(item1);
        iterableList.addToList(item2);
        iterableList.addToList(item3);

        // Get all list members
        address[] memory members = iterableList.getAllListMembers();
        assertEq(members.length, 3);
        assertEq(members[0], item1);
        assertEq(members[1], item2);
        assertEq(members[2], item3);
    }

    function testContains() public {
        // Add an item and check contains
        vm.prank(address(this));
        iterableList.addToList(item1);
        assertTrue(iterableList.contains(item1));

        // Check an item not in the list
        assertFalse(iterableList.contains(item2));
    }

    function testInvalidAdditions() public {
        // Attempt to add zero address, expect revert
        vm.expectRevert("Cannot add zero address");
        iterableList.addToList(address(0));

        // Attempt to add placeholder addresses, expect revert
        vm.expectRevert("Cannot add last arbitrator");
        iterableList.addToList(iterableList.PLACEHOLDER_LAST_ITEM());

        vm.expectRevert("Cannot add first arbitrator");
        iterableList.addToList(iterableList.PLACEHOLDER_FIRST_ITEM());
    }

    function testInvalidRemovals() public {
        // Attempt to remove zero address, expect revert
        vm.expectRevert("Cannot remove zero address");
        iterableList.removeFromList(address(0));

        // Attempt to remove placeholder addresses, expect revert
        vm.expectRevert("Cannot remove last arbitrator");
        iterableList.removeFromList(iterableList.PLACEHOLDER_LAST_ITEM());

        vm.expectRevert("Cannot remove first arbitrator");
        iterableList.removeFromList(iterableList.PLACEHOLDER_FIRST_ITEM());
    }
}
