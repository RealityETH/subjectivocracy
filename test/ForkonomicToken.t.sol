pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ForkonomicToken} from "../contracts/ForkonomicToken.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import {IForkonomicToken} from "../contracts/interfaces/IForkonomicToken.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract ForkonomicTokenTest is Test {
    ForkonomicToken public forkonomicToken;

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

        vm.expectRevert(IForkonomicToken.NotMinterRole.selector);
        forkonomicToken.mint(address(this), mintAmount);
    }

    function testCreateChildrenAndSplitTokens() public {
        vm.prank(forkonomicToken.forkmanager());
        (address child1, address child2) = forkonomicToken.createChildren();
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
