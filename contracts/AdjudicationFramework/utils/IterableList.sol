pragma solidity ^0.8.20;

/*
    contract that contains an iterable list.
*/

// Unfortuneately, openzepplin does not provide such a contract out of the box. It only has
// library EnumerableSet, which is similar, but would require to store everything in bytes32, instead of just addresses.

contract IterableList {
    address public constant PLACEHOLDER_LAST_ITEM = address(1);
    address public constant PLACEHOLDER_FIRST_ITEM = address(2);

    mapping(address => address) public nextItem;
    mapping(address => address) public previousItem;

    function contains(address item) public view returns (bool) {
        if (item == PLACEHOLDER_LAST_ITEM) {
            return false;
        }
        return nextItem[item] != address(0);
    }

    /**
     * @dev Adds an item to the list
     * @param item The item to add to the list
     */

    function _addToList(address item) internal {
        require(item != address(0), "Cannot add zero address");
        require(item != PLACEHOLDER_LAST_ITEM, "Cannot add last arbitrator");
        require(item != PLACEHOLDER_FIRST_ITEM, "Cannot add first arbitrator");
        require(
            nextItem[item] == address(0),
            "Cannot add item that is already in list"
        );

        address lastMember = previousItem[PLACEHOLDER_LAST_ITEM];
        nextItem[lastMember] = item;
        previousItem[item] = lastMember;
        nextItem[item] = PLACEHOLDER_LAST_ITEM;
        previousItem[PLACEHOLDER_LAST_ITEM] = item;
    }

    /**
     * @dev Removes an item from the list
     * @param memberToRemove The item to remove from the list
     */
    function _removeFromList(address memberToRemove) internal {
        require(memberToRemove != address(0), "Cannot remove zero address");
        require(
            memberToRemove != PLACEHOLDER_LAST_ITEM,
            "Cannot remove last arbitrator"
        );
        require(
            memberToRemove != PLACEHOLDER_FIRST_ITEM,
            "Cannot remove first arbitrator"
        );
        require(
            nextItem[memberToRemove] != address(0),
            "Cannot remove arbitrator that is not in list"
        );

        address previousMember = previousItem[memberToRemove];
        address nextMember = nextItem[memberToRemove];

        nextItem[previousMember] = nextMember;
        previousItem[nextMember] = previousMember;
        nextItem[memberToRemove] = address(0);
        previousItem[memberToRemove] = address(0);
    }

    /**
     * @dev Returns the number of items in the list
     * @return The number of items in the list
     */
    function getNumberOfListMembers() public view returns (uint256) {
        uint256 count = 0;
        address currentMember = nextItem[PLACEHOLDER_FIRST_ITEM];
        while (currentMember != PLACEHOLDER_LAST_ITEM) {
            count++;
            currentMember = nextItem[currentMember];
        }
        return count;
    }

    /**
     * @dev Returns the list of items
     * @return members The list of members
     */
    function getAllListMembers()
        public
        view
        returns (address[] memory members)
    {
        members = new address[](getNumberOfListMembers());
        address currentMember = nextItem[PLACEHOLDER_FIRST_ITEM];
        for (uint256 i = 0; i < members.length; i++) {
            members[i] = currentMember;
            currentMember = nextItem[currentMember];
        }
    }
}
