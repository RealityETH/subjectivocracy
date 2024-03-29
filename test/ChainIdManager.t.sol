pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol"; // Hypothetical test library
import {ChainIdManager} from "../contracts/ChainIdManager.sol"; // Path to the ChainIdManager contract

contract ChainIdManagerTest is Test {
    ChainIdManager public chainIdManager;

    address public owner = address(0xabc);
    address public nonOwner = address(0xdef);
    uint64 public initialChainId = 10;

    function setUp() public {
        chainIdManager = new ChainIdManager(initialChainId);
    }

    function testAddChainId() public {
        uint64 newChainId = 10;
        chainIdManager.denyListChainId(newChainId);

        assertEq(
            chainIdManager.getNextUsableChainId(),
            newChainId + 1,
            "Chain ID not correctly added"
        );

        // Attempt to add a ChainId by a non-owner, expect a consumption of gas
        uint256 currentGas = gasleft();
        chainIdManager.denyListChainId(2);
        uint256 finalGas = gasleft();
        assert(currentGas - finalGas >= chainIdManager.GAS_BURN_AMOUNT());

        uint256 currentGas2 = gasleft();
        uint64[] memory newChainIds = new uint64[](6);
        newChainIds[0] = 3;
        newChainIds[1] = 4;
        newChainIds[2] = 5;
        newChainIds[3] = 6;
        newChainIds[4] = 7;
        newChainIds[5] = 8;
        chainIdManager.denyListChainIds(newChainIds);
        uint256 finalGas2 = gasleft();
        assert(currentGas2 - finalGas2 >= chainIdManager.GAS_BURN_AMOUNT() * 6);
    }

    function testAddChainIds() public {
        vm.prank(owner);
        uint64[] memory newChainIds = new uint64[](2);
        newChainIds[0] = 10;
        newChainIds[1] = 11;
        chainIdManager.denyListChainIds(newChainIds);

        assertEq(
            chainIdManager.chainIdCounter(),
            initialChainId,
            "Chain ID counter did not increment correctly"
        );
        assertEq(
            chainIdManager.getNextUsableChainId(),
            newChainIds[1] + 1,
            "First Chain ID not correctly added"
        );
    }

    function testGetNextUsableChainId() public {
        uint64 firstDeniedChainId = 10;
        vm.prank(owner);
        chainIdManager.denyListChainId(firstDeniedChainId);
        uint64 secondDeniedChainId = 11;
        vm.prank(owner);
        chainIdManager.denyListChainId(secondDeniedChainId);

        uint64 nextChainId = chainIdManager.getNextUsableChainId();
        assertEq(
            nextChainId,
            secondDeniedChainId + 1,
            "Did not get the correct next usable Chain ID"
        );

        nextChainId = chainIdManager.getNextUsableChainId();
        assertEq(
            nextChainId,
            secondDeniedChainId + 2,
            "Did not get the correct next usable Chain ID"
        );
    }

    function testCheckGasBurn() public view {
        uint256 initialGasLeft = gasleft();
        chainIdManager.burnGas();
        uint256 finalGasLeft = gasleft();
        assert(
            initialGasLeft - finalGasLeft >= chainIdManager.GAS_BURN_AMOUNT()
        );
    }
}
