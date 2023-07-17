pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {ForkableUUPSWrapper} from "./testcontract/ForkableUUPSWrapper.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Util} from "./utils/Util.sol";

contract ForkableUUPSTest is Test {
    ForkableUUPSWrapper public forkableUUPS;

    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address public forkmanager = address(0x123);
    address public parentContract = address(0x456);
    address public updater =
        address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38);
    address public forkableUUPSImplementation;

    function setUp() public {
        forkableUUPSImplementation = address(new ForkableUUPSWrapper());
        forkableUUPS = ForkableUUPSWrapper(
            address(new ERC1967Proxy(forkableUUPSImplementation, ""))
        );
        forkableUUPS.initialize(forkmanager, parentContract, updater);
    }

    function testInitialize() public {
        assertEq(forkableUUPS.forkmanager(), forkmanager);
        assertEq(forkableUUPS.parentContract(), parentContract);
        assertTrue(forkableUUPS.hasRole(forkableUUPS.UPDATER(), updater));
    }

    function testCreateChildren() public {
        address secondForkableUUPSImplementation = address(
            new ForkableUUPSWrapper()
        );

        (address child1, address child2) = forkableUUPS.createChildren(
            secondForkableUUPSImplementation
        );

        // child1 and child2 addresses should not be zero address
        assertTrue(child1 != address(0));
        assertTrue(child2 != address(0));

        // the implementation address of children should match the expected ones
        assertEq(
            Util.bytesToAddress(
                vm.load(address(child1), _IMPLEMENTATION_SLOT)
            ),
            forkableUUPSImplementation
        );
        assertEq(
            Util.bytesToAddress(
                vm.load(address(child2), _IMPLEMENTATION_SLOT)
            ),
            secondForkableUUPSImplementation
        );
    }

    function testUpdaterUpgradeAuthorization() public {
        assertTrue(forkableUUPS.hasRole(forkableUUPS.UPDATER(), updater));
        vm.prank(updater);
        forkableUUPS.authorizationCheck(updater);

        vm.expectRevert(bytes("Caller is not an updater"));
        forkableUUPS.authorizationCheck(updater);
    }
}
