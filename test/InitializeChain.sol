// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {InitializeChainWrapper} from "./testcontract/InitializeChainWrapper.sol";
import {InitializeChain} from "../contracts/mixin/InitializeChain.sol";

contract InitializeChainWrapperTest is Test {
    InitializeChainWrapper public wrapper;

    function setUp() public {
        wrapper = new InitializeChainWrapper();
    }

    function testSetChainId() public {
        assertEq(wrapper.chainId(), block.chainid);
    }

    function testonlyChainUninitialized() public {
        // Simulate a chain fork by setting block.chainid to a new value
        vm.chainId(2);
        wrapper.onlyChainUninitializedWrapper(); // This should pass since it's the first TX after fork

        // Subsequent calls should fail
        vm.expectRevert(InitializeChain.NotOnNewFork.selector);
        wrapper.onlyChainUninitializedWrapper();
    }

    function testonlyChainInitialized() public {
        // On the original chain, this call should succeed
        wrapper.onlyChainInitializedWrapper();

        // Simulate a chain fork by setting block.chainid to a new value
        vm.chainId(2);

        // This call should fail since it's the first TX after fork
        vm.expectRevert(InitializeChain.OnNewFork.selector);
        wrapper.onlyChainInitializedWrapper();

        // Call a function with onlyChainUninitialized to update chainId
        wrapper.onlyChainUninitializedWrapper();

        // Now, this call should succeed
        wrapper.onlyChainInitializedWrapper();
    }

    function testUpdateChainId() public {
        // Initially, chainId is 1
        assertFalse(wrapper.chainId() == 1);

        // Simulate a chain fork by setting block.chainid to a new value
        vm.chainId(2);
        wrapper.onlyChainUninitializedWrapper(); // This should update the chainId

        assertEq(wrapper.chainId(), 2);
    }
}
