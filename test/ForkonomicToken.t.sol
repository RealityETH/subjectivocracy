pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {ForkonomicToken} from "../development/contracts/ForkonomicToken.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import {IForkonomicToken} from "../development/contracts/interfaces/IForkonomicToken.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Util} from "./utils/Util.sol";

contract ForkonomicTokenTest is Test {
    ForkonomicToken public forkonomicToken;

    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address public forkmanager = address(0x123);
    address public parentContract = address(0x456);
    address public minter = address(0x789);
    address public forkonomicTokenImplementation;
    address public admin = address(0xad);

    function setUp() public {
        forkonomicTokenImplementation = address(new ForkonomicToken());
        forkonomicToken = ForkonomicToken(
            address(
                new TransparentUpgradeableProxy(
                    forkonomicTokenImplementation,
                    admin,
                    ""
                )
            )
        );
        forkonomicToken.initialize(
            forkmanager,
            parentContract,
            minter,
            "ForkonomicToken",
            "FTK"
        );
    }

    function testInitialize() public {
        assertEq(forkonomicToken.forkmanager(), forkmanager);
        assertEq(forkonomicToken.parentContract(), parentContract);
        assertTrue(
            forkonomicToken.hasRole(forkonomicToken.MINTER_ROLE(), minter)
        );
        assertEq(forkonomicToken.name(), "ForkonomicToken");
        assertEq(forkonomicToken.symbol(), "FTK");
    }

    function testMint() public {
        uint256 mintAmount = 1000;
        vm.prank(minter);
        forkonomicToken.mint(address(this), mintAmount);

        assertEq(forkonomicToken.balanceOf(address(this)), mintAmount);

        vm.expectRevert(bytes("Caller is not a minter"));
        forkonomicToken.mint(address(this), mintAmount);
    }

    function testCreateChildrenAndSplitTokens() public {
        address forkonomicTokenImplementation2 = address(new ForkonomicToken());
        vm.prank(forkonomicToken.forkmanager());
        (address child1, address child2) = forkonomicToken.createChildren(
            forkonomicTokenImplementation2
        );
        ForkonomicToken(child1).initialize(
            forkmanager,
            address(forkonomicToken),
            minter,
            "ForkonomicToken",
            "FTK"
        );
        ForkonomicToken(child2).initialize(
            forkmanager,
            address(forkonomicToken),
            minter,
            "ForkonomicToken",
            "FTK"
        );

        // test splitTokensIntoChildTokens
        uint256 splitAmount = 500;
        vm.prank(minter);
        forkonomicToken.mint(address(this), splitAmount);
        assertEq(forkonomicToken.balanceOf(address(this)), splitAmount);

        forkonomicToken.splitTokensIntoChildTokens(splitAmount);

        // check that the balance of this contract has decreased
        assertEq(forkonomicToken.balanceOf(address(this)), 0);

        // check that the balance of this contract in the child contracts has increased
        assertEq(
            IERC20Upgradeable(child1).balanceOf(address(this)),
            splitAmount
        );
        assertEq(
            IERC20Upgradeable(child2).balanceOf(address(this)),
            splitAmount
        );
    }
}
