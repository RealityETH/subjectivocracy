pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {L2ChainInfo} from "../contracts/L2ChainInfo.sol"; // Adjust the path as necessary

contract L2ChainInfoTest is Test {
    L2ChainInfo public l2ChainInfo;

    address public l2Bridge = address(0x123);
    address public l1GlobalChainInfoPublisher = address(0x456);
    address public nonBridge = address(0x789);
    uint64 public testChainId = 1;
    address public forkonomicToken = address(0xabc);
    uint256 public forkFee = 100;
    bool public isL1 = true;
    address public forker = address(0xdef);
    bytes32 public questionId = keccak256("test question");
    bytes32 public result = keccak256("test result");

    function setUp() public {
        l2ChainInfo = new L2ChainInfo(l2Bridge, l1GlobalChainInfoPublisher);
    }

    function testUpdateChainInfo() public {
        bytes memory data = abi.encode(
            block.chainid,
            forkonomicToken,
            forkFee,
            isL1,
            forker,
            questionId,
            result
        );

        vm.prank(l2Bridge);
        l2ChainInfo.onMessageReceived(l1GlobalChainInfoPublisher, 0, data);

        assertEq(
            l2ChainInfo.getForkonomicToken(),
            forkonomicToken,
            "Forkonomic token not updated correctly"
        );
        assertEq(
            l2ChainInfo.getForkFee(),
            forkFee,
            "Fork fee not updated correctly"
        );
        assertEq(
            l2ChainInfo.getForkQuestionResult(isL1, forker, questionId),
            result,
            "Fork question result not updated correctly"
        );
    }

    function testUpdateChainInfoNonBridge() public {
        bytes memory data = abi.encode(
            testChainId,
            forkonomicToken,
            forkFee,
            isL1,
            forker,
            questionId,
            result
        );

        vm.expectRevert(L2ChainInfo.OnlyBridge.selector);
        vm.prank(nonBridge);
        l2ChainInfo.onMessageReceived(l1GlobalChainInfoPublisher, 0, data);
    }

    function testQueryBeforeUpdate() public {
        vm.expectRevert(L2ChainInfo.ChainInfoNotKnown.selector);
        l2ChainInfo.getForkonomicToken();

        vm.expectRevert(L2ChainInfo.ChainInfoNotKnown.selector);
        l2ChainInfo.getForkFee();

        vm.expectRevert(L2ChainInfo.ChainInfoNotKnown.selector);
        l2ChainInfo.getForkQuestionResult(isL1, forker, questionId);
    }

    function testUpdateWithBadOrigin() public {
        bytes memory data = abi.encode(
            testChainId,
            forkonomicToken,
            forkFee,
            isL1,
            forker,
            questionId,
            result
        );

        // Test with incorrect origin address
        vm.expectRevert(L2ChainInfo.OriginMustBePublisher.selector);
        vm.prank(l2Bridge);
        l2ChainInfo.onMessageReceived(nonBridge, 0, data);
    }
}
