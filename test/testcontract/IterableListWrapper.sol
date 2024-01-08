// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;
import {IterableList} from "../../contracts/AdjudicationFramework/utils/IterableList.sol";

contract IterableListWrapper is IterableList {
    function addToList(address item) public {
        _addToList(item);
    }

    function removeFromList(address item) public {
        _removeFromList(item);
    }
}
