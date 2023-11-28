pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {MoneyBox} from "../contracts/mixin/MoneyBox.sol";
import {MoneyBoxUser} from "../contracts/mixin/MoneyBoxUser.sol";

import {ExampleToken} from "./testcontract/ExampleToken.sol";
import {ExampleMoneyBoxUser} from "./testcontract/ExampleMoneyBoxUser.sol";

contract MoneyBoxTest is Test {

    ExampleToken internal token;
    bytes32 internal salt = bytes32("0xbabebabe");

    address internal user1 = address(0xc0ffee01);
    address internal user2 = address(0xc0ffee02);

    function setUp() public {
        vm.prank(user1);
        token = new ExampleToken();
    }

    function testCreatorApproved() public {
        vm.recordLogs();
        vm.prank(user2);
        new MoneyBox{salt: salt}(address(token));
        Vm.Log[] memory entries = vm.getRecordedLogs();
        address approvedUser = address(uint160(uint256(entries[0].topics[2])));
        assertEq(approvedUser, user2);
        uint256 approveAmount = abi.decode(entries[0].data, (uint256));
        assertEq(approveAmount, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    }

    function testCreatorCanTakeTokens() public {

        // We'll credit the tokens before deploying the contract as this is the order it will be done in in real life
        ExampleMoneyBoxUser exampleMoneyBoxUser = new ExampleMoneyBoxUser();
        address calculatedAddress = exampleMoneyBoxUser.calculateMoneyBoxAddress(user1, salt, address(token));
        token.fakeMint(calculatedAddress, 10000123);

        vm.prank(user1);
        MoneyBox moneyBox = new MoneyBox{salt: salt}(address(token));
        vm.prank(user2);
        vm.expectRevert(bytes("ERC20: insufficient allowance"));
        token.transferFrom(address(moneyBox), user2, 123);
        vm.prank(user1);
        token.transferFrom(address(moneyBox), user2, 123);

        assertEq(token.balanceOf(address(moneyBox)), 10000123 - 123);
        assertEq(token.balanceOf(user2), 123);

    }

    function testAddressCalculation() public {

        vm.prank(user2);
        MoneyBox moneyBox = new MoneyBox{salt: salt}(address(token));
        ExampleMoneyBoxUser exampleMoneyBoxUser = new ExampleMoneyBoxUser();
        address calculatedAddress = exampleMoneyBoxUser.calculateMoneyBoxAddress(user2, salt, address(token));
        assertEq(calculatedAddress, address(moneyBox));

        address calculatedAddress2 = exampleMoneyBoxUser.calculateMoneyBoxAddress(user1, salt, address(token));
        assertNotEq(calculatedAddress2, address(moneyBox));

        address calculatedAddress3 = exampleMoneyBoxUser.calculateMoneyBoxAddress(user2, bytes32("0xee00bb"), address(token));
        assertNotEq(calculatedAddress3, address(moneyBox));

        address calculatedAddress4 = exampleMoneyBoxUser.calculateMoneyBoxAddress(user2, salt, address(0xee00bb));
        assertNotEq(calculatedAddress4, address(moneyBox));

    }

}
