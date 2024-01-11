pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ForkableStructureWrapper} from "./testcontract/ForkableStructureWrapper.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Util} from "./utils/Util.sol";
import {IForkableStructure} from "../contracts/interfaces/IForkableStructure.sol";

contract ForkStructureTest is Test {
    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    bytes32 internal constant _ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    ForkableStructureWrapper public forkStructure;

    address public forkableStructureImplementation;

    address public forkmanager = address(0x123);
    address public parentContract = address(0x456);
    address public admin = address(0xad);

    function setUp() public {
        forkStructure = new ForkableStructureWrapper();
        forkStructure.initialize(forkmanager, parentContract);
    }

    function testInitialize() public {
        assertEq(forkStructure.forkmanager(), forkmanager);
        assertEq(forkStructure.parentContract(), parentContract);
    }

    function testGetChildren() public {
        address child1 = address(0x789);
        address child2 = address(0xabc);
        // assume the contract has a setChild function
        forkStructure.setChild(0, child1);
        forkStructure.setChild(1, child2);
        (address returnedChild1, address returnedChild2) = forkStructure
            .getChildren();
        assertEq(returnedChild1, child1);
        assertEq(returnedChild2, child2);
    }

    function testCreateChildren() public {
        forkableStructureImplementation = address(
            new ForkableStructureWrapper()
        );
        forkStructure = ForkableStructureWrapper(
            address(
                new TransparentUpgradeableProxy(
                    forkableStructureImplementation,
                    admin,
                    ""
                )
            )
        );
        forkStructure.initialize(forkmanager, parentContract);

        (address child1, address child2) = forkStructure.createChildren();

        // child1 and child2 addresses should not be zero address
        assertTrue(child1 != address(0));
        assertTrue(child2 != address(0));

        // the implementation address of children should match the expected ones
        assertEq(
            Util.bytesToAddress(vm.load(address(child1), _IMPLEMENTATION_SLOT)),
            forkableStructureImplementation
        );
        assertEq(
            Util.bytesToAddress(vm.load(address(child2), _IMPLEMENTATION_SLOT)),
            forkableStructureImplementation
        );
        assertEq(
            Util.bytesToAddress(vm.load(address(child1), _ADMIN_SLOT)),
            admin
        );
        assertEq(
            Util.bytesToAddress(vm.load(address(child2), _ADMIN_SLOT)),
            admin
        );
    }

    function testModifiers() public{
        forkableStructureImplementation = address(
            new ForkableStructureWrapper()
        );
        forkStructure = ForkableStructureWrapper(
            address(
                new TransparentUpgradeableProxy(
                    forkableStructureImplementation,
                    admin,
                    ""
                )
            )
        );
        forkStructure.initialize(forkmanager, parentContract);

        forkStructure.onlyBeforeForkingTesting();
        vm.expectRevert(IForkableStructure.OnlyAfterForking.selector);
        forkStructure.onlyAfterForkingTesting();

        forkStructure.createChildren();
        
        vm.expectRevert(IForkableStructure.NoChangesAfterForking.selector);
        forkStructure.onlyBeforeForkingTesting();
        forkStructure.onlyAfterForkingTesting();

        vm.expectRevert(IForkableStructure.OnlyParentIsAllowed.selector);
        forkStructure.onlyParentContractTesting();

        vm.expectRevert(IForkableStructure.OnlyForkManagerIsAllowed.selector);
        forkStructure.onlyForkManagerTesting();

        vm.prank(forkStructure.forkmanager());
        forkStructure.onlyForkManagerTesting();

        vm.prank(forkStructure.parentContract());
        forkStructure.onlyParentContractTesting();
    }
}
