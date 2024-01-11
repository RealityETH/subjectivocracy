// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Util} from "./utils/Util.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {CreateChildrenWrapper} from "./testcontract/CreateChildrenWrapper.sol";

// Create a test suite contract
contract CreateChildrenTest is Test {
    CreateChildrenWrapper public testContract;
    address public admin = address(0x987654321);
    address public implementation = address(new CreateChildrenWrapper());
    // Deploy the test contract before running tests
    constructor() {
        testContract = CreateChildrenWrapper(
            address(new TransparentUpgradeableProxy(implementation, admin, ""))
        );
    }

    // Test case to check if the implementation address is correctly set
    function testImplementationAddress() external {
        address receivedImplementation = testContract.getImplementation();
        assertEq(
            receivedImplementation,
            implementation,
            "Implementation address is incorrect"
        );
    }

    // Test case to check if the admin address is correctly set
    function testAdminAddress() external {
        address receivedAdmin = testContract.getAdmin();
        assertEq(receivedAdmin, admin, "Admin address is incorrect");
    }

    // Test case to create children contracts and check their addresses
    function testCreateChildren() external {
        (address child1, address child2) = testContract.createChildren();
        // Test implementation slot with two different ways
        assertEq(
            Util.bytesToAddress(
                vm.load(address(child2), Util._IMPLEMENTATION_SLOT)
            ),
            implementation
        );
        assertEq(
            CreateChildrenWrapper(child1).getImplementation(),
            implementation
        );
        // Test admin slot with two different ways
        assertEq(
            Util.bytesToAddress(vm.load(address(child1), Util._ADMIN_SLOT)),
            admin
        );
        assertEq(CreateChildrenWrapper(child1).getAdmin(), admin);

        assertEq(
            Util.bytesToAddress(
                vm.load(address(child2), Util._IMPLEMENTATION_SLOT)
            ),
            implementation
        );
        assertEq(
            Util.bytesToAddress(vm.load(address(child2), Util._ADMIN_SLOT)),
            admin
        );
    }
}
