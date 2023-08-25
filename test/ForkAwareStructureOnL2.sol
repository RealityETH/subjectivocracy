// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {ForkAwareStructureOnL2Wrapper} from "./testcontract/ForkAwareStructureOnL2Wrapper.sol";

contract ForkAwareStructureOnL2WrapperTest is Test {
    ForkAwareStructureOnL2Wrapper public wrapper;

    function setUp() public {
        wrapper = new ForkAwareStructureOnL2Wrapper();
    }

    function testSetChainId() public {
        assertEq(wrapper.chainId(), block.chainid);
    }

    function testOnlyFirstTxAfterFork() public {
        // Simulate a chain fork by setting block.chainid to a new value
        vm.chainId(2);
        wrapper.onlyFirstTxAfterForkWrapper(); // This should pass since it's the first TX after fork

        // Subsequent calls should fail
        try wrapper.onlyFirstTxAfterForkWrapper() {
            fail(
                "Should have reverted because it's not the first TX after fork."
            );
        } catch Error(string memory reason) {
            assertEq(reason, "Not on new fork");
        }
    }

    function testEveryButFirstTxAfterFork() public {
        // On the original chain, this call should succeed
        wrapper.everyButFirstTxAfterForkWrapper();

        // Simulate a chain fork by setting block.chainid to a new value
        vm.chainId(2);

        // This call should fail since it's the first TX after fork
        try wrapper.everyButFirstTxAfterForkWrapper() {
            fail("Should have reverted because it's the first TX after fork.");
        } catch Error(string memory reason) {
            assertEq(reason, "On new fork");
        }

        // Call a function with onlyFirstTxAfterFork to update chainId
        wrapper.onlyFirstTxAfterForkWrapper();

        // Now, this call should succeed
        wrapper.everyButFirstTxAfterForkWrapper();
    }

    function testUpdateChainId() public {
        // Initially, chainId is 1
        assertFalse(wrapper.chainId() == 1);

        // Simulate a chain fork by setting block.chainid to a new value
        vm.chainId(2);
        wrapper.onlyFirstTxAfterForkWrapper(); // This should update the chainId

        assertEq(wrapper.chainId(), 2);
    }
}
