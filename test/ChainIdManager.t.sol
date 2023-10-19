pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol"; // Hypothetical test library
import {ChainIdManager} from "../contracts/ChainIdManager.sol"; // Path to the ChainIdManager contract
import {Util} from "./utils/Util.sol"; // Hypothetical utilities for testing

contract ChainIdManagerTest is Test {
    ChainIdManager public chainIdManager;

    address public owner = address(0xabc);
    address public nonOwner = address(0xdef);

    function setUp() public {
        chainIdManager = new ChainIdManager();
        chainIdManager.transferOwnership(owner);
    }

    function testAddChainId() public {
        vm.prank(owner);
        uint64 newChainId = 1;
        chainIdManager.addChainId(newChainId);

        assertEq(
            chainIdManager.chainIdCounter(),
            1,
            "Chain ID counter did not increment"
        );
        assertEq(
            chainIdManager.usableChainIds(0),
            newChainId,
            "Chain ID not correctly added"
        );

        // Attempt to add a ChainId by a non-owner, expect a revert
        vm.prank(nonOwner);
        vm.expectRevert(bytes("Caller is not the owner")); // Expect a revert with a specific revert message
        chainIdManager.addChainId(2);
    }

    function testAddChainIds() public {
        vm.prank(owner);
        uint64[] memory newChainIds = new uint64[](2);
        newChainIds[0] = 1;
        newChainIds[1] = 2;
        chainIdManager.addChainIds(newChainIds);

        assertEq(
            chainIdManager.chainIdCounter(),
            2,
            "Chain ID counter did not increment correctly"
        );
        assertEq(
            chainIdManager.usableChainIds(0),
            newChainIds[0],
            "First Chain ID not correctly added"
        );
        assertEq(
            chainIdManager.usableChainIds(1),
            newChainIds[1],
            "Second Chain ID not correctly added"
        );
    }

    function testGetNextUsableChainId() public {
        vm.prank(owner);
        chainIdManager.addChainId(1);
        vm.prank(owner);
        chainIdManager.addChainId(2);

        uint64 nextChainId = chainIdManager.getNextUsableChainId();
        assertEq(
            nextChainId,
            1,
            "Did not get the correct next usable Chain ID"
        );
        assertEq(
            chainIdManager.usedChainIdCounter(),
            1,
            "Used Chain ID counter did not increment"
        );

        nextChainId = chainIdManager.getNextUsableChainId();
        assertEq(
            nextChainId,
            2,
            "Did not get the correct next usable Chain ID"
        );
        assertEq(
            chainIdManager.usedChainIdCounter(),
            2,
            "Used Chain ID counter did not increment"
        );

        // Assuming that there's no Chain ID left, expect a revert or a return of a default value depending on the contract's behavior
        vm.expectRevert(bytes("No usable Chain ID available")); // Or check for a specific return value
        chainIdManager.getNextUsableChainId();
    }
}
