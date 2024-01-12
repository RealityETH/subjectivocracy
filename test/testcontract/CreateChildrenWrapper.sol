// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

// Import the library you want to test
import {CreateChildren} from "../../contracts/lib/CreateChildren.sol";

contract CreateChildrenWrapper {
    // Constructor to set initial values in storage slots
    constructor() {}

    // Function to get the current implementation address for testing purposes
    function getImplementation() external view returns (address) {
        return CreateChildren.getImplementation();
    }

    // Function to get the current admin address for testing purposes
    function getAdmin() external view returns (address) {
        return CreateChildren.getAdmin();
    }

    // Function to create children contracts using the library
    function createChildren()
        external
        returns (address child1, address child2)
    {
        return CreateChildren.createChildren();
    }
}
