pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {ForkableGlobalExitRoot} from "../development/contracts/ForkableGlobalExitRoot.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Util} from "./utils/Util.sol";

contract ForkableGlobalExitRootTest is Test {
    ForkableGlobalExitRoot public forkableGlobalExitRoot;

    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address public forkmanager = address(0x123);
    address public parentContract = address(0x456);
    address public updater =
        address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38);
    address public rollupAddress = address(0x789);
    address public bridgeAddress = address(0xabc);
    address public forkableGlobalExitRootImplementation;

    function setUp() public {
        forkableGlobalExitRootImplementation = address(
            new ForkableGlobalExitRoot()
        );
        forkableGlobalExitRoot = ForkableGlobalExitRoot(
            address(new ERC1967Proxy(forkableGlobalExitRootImplementation, ""))
        );
        forkableGlobalExitRoot.initialize(
            forkmanager,
            parentContract,
            rollupAddress,
            bridgeAddress
        );
    }

    function testInitialize() public {
        assertEq(forkableGlobalExitRoot.forkmanager(), forkmanager);
        assertEq(forkableGlobalExitRoot.parentContract(), parentContract);
        assertTrue(
            forkableGlobalExitRoot.hasRole(
                forkableGlobalExitRoot.DEFAULT_ADMIN_ROLE(),
                address(this)
            )
        );
    }

    function testCreateChildren() public {
        address secondForkableGlobalExitRootImplementation = address(
            new ForkableGlobalExitRoot()
        );
        vm.prank(forkableGlobalExitRoot.forkmanager());
        (address child1, address child2) = forkableGlobalExitRoot
            .createChildren(secondForkableGlobalExitRootImplementation);

        // child1 and child2 addresses should not be zero address
        assertTrue(child1 != address(0));
        assertTrue(child2 != address(0));

        // the implementation address of children should match the expected ones
        assertEq(
            Util.bytesToAddress(vm.load(address(child1), _IMPLEMENTATION_SLOT)),
            forkableGlobalExitRootImplementation
        );
        assertEq(
            Util.bytesToAddress(vm.load(address(child2), _IMPLEMENTATION_SLOT)),
            secondForkableGlobalExitRootImplementation
        );
    }

    function testCreateChildrenOnlyByForkManager() public {
        address secondForkableGlobalExitRootImplementation = address(
            new ForkableGlobalExitRoot()
        );

        vm.expectRevert("Only forkManager is allowed");
        forkableGlobalExitRoot.createChildren(
            secondForkableGlobalExitRootImplementation
        );
        vm.prank(forkableGlobalExitRoot.forkmanager());
        forkableGlobalExitRoot.createChildren(
            secondForkableGlobalExitRootImplementation
        );
    }
}
