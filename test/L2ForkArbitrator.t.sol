pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {L2ForkArbitrator} from "../contracts/L2ForkArbitrator.sol";
import {IRealityETH} from "../contracts/lib/reality-eth/interfaces/IRealityETH.sol";
import {L2ChainInfo} from "../contracts/L2ChainInfo.sol";
import {L1GlobalForkRequester} from "../contracts/L1GlobalForkRequester.sol";
import {IL2ForkArbitrator} from "../contracts/interfaces/IL2ForkArbitrator.sol";

contract L2ForkArbitratorTest is Test {
    L2ForkArbitrator public arbitrator;
    address public realitio;
    address public chainInfo;
    address public l1GlobalForkRequester;
    uint256 public initialDisputeFee = 1 ether;

    function setUp() public {
        // Mock the dependencies
        realitio = address(0x121); // Replace with the actual mock contract
        chainInfo = address(0x122); // Replace with the actual mock contract
        l1GlobalForkRequester = address(0x123); // Replace with the actual mock contract

        arbitrator = new L2ForkArbitrator(
            IRealityETH(realitio),
            L2ChainInfo(chainInfo),
            L1GlobalForkRequester(l1GlobalForkRequester),
            initialDisputeFee
        );
    }

    function testInitialSetup() public {
        assertEq(
            arbitrator.getDisputeFee(bytes32(0)),
            initialDisputeFee,
            "Initial dispute fee is incorrect"
        );
    }

    function testRequestArbitration() public {
        bytes32 questionId = bytes32("TestQuestionId");
        uint256 maxPrevious = 0;
        uint256 arbitrationFee = arbitrator.getDisputeFee(questionId);
        vm.mockCall(
            realitio,
            abi.encodeWithSelector(
                IRealityETH.notifyOfArbitrationRequest.selector,
                questionId,
                address(this),
                maxPrevious
            ),
            abi.encode()
        );
        // Simulate a successful arbitration request
        vm.deal(address(this), arbitrationFee);
        bool success = arbitrator.requestArbitration{value: arbitrationFee}(
            questionId,
            maxPrevious
        );
        assertTrue(success, "Arbitration request should succeed");

        // Test for re-entrancy or double request
        vm.expectRevert(IL2ForkArbitrator.ArbitrationAlreadyRequested.selector);
        vm.deal(address(this), arbitrationFee);
        arbitrator.requestArbitration{value: arbitrationFee}(
            questionId,
            maxPrevious
        );
    }

    function testRequestActivateFork() public {
        uint256 maxPrevious = 0;
        uint256 delay = 60 * 60; // 1 hour
        uint256 templateId = 1;
        string memory question = "TestQuestion";
        uint256 minBond = 1 ether;
        uint32 openingTs = uint32(block.timestamp);
        uint256 nonce = 1;
        bytes32 contentHash = keccak256(
            abi.encodePacked(templateId, openingTs, question)
        );
        bytes32 questionId = keccak256(
            abi.encodePacked(
                contentHash,
                address(arbitrator),
                uint32(300), // timeout,
                minBond,
                address(realitio),
                address(this),
                nonce
            )
        );

        vm.mockCall(
            realitio,
            abi.encodeWithSelector(
                IRealityETH.notifyOfArbitrationRequest.selector,
                questionId,
                address(this),
                maxPrevious
            ),
            abi.encode()
        );

        vm.deal(address(this), 1 ether);
        arbitrator.requestArbitration{value: 1 ether}(questionId, maxPrevious);

        // Attempt to activate fork
        vm.mockCall(
            address(this),
            abi.encodeWithSelector(
                bytes4(keccak256("getInvestigationDelay()"))
            ),
            abi.encode(delay)
        );
        vm.expectRevert(IL2ForkArbitrator.RequestStillInWaitingPeriod.selector);
        arbitrator.requestActivateFork(
            templateId,
            openingTs,
            question,
            300, // timeout,
            minBond,
            nonce,
            address(this)
        );

        // Simulate passage of time
        vm.warp(block.timestamp + delay + 1);
        vm.mockCall(
            chainInfo,
            abi.encodeWithSelector(L2ChainInfo.getForkFee.selector),
            abi.encode(1)
        );
        vm.mockCall(
            chainInfo,
            abi.encodeWithSelector(bytes4(keccak256("l2Bridge()"))),
            abi.encode(address(0x1654))
        );
        vm.mockCall(
            address(0x1654), // l2 bridge contract
            abi.encodeWithSelector(bytes4(keccak256("bridgeAsset()"))),
            abi.encode()
        );
        vm.mockCall(
            chainInfo,
            abi.encodeWithSelector(bytes4(keccak256("getForkonomicToken()"))),
            abi.encode(address(0x16542))
        );
        vm.deal(address(arbitrator), 1 ether);
        arbitrator.requestActivateFork(
            templateId,
            openingTs,
            question,
            300, // timeout,
            minBond,
            nonce,
            address(this)
        );
    }

    function testANewRequestDoesNotHaveToWaitAgain() public {
        uint256 maxPrevious = 0;
        uint256 delay = 60 * 60; // 1 hour
        uint256 templateId = 1;
        string memory question = "TestQuestion";
        uint256 minBond = 1 ether;
        uint32 openingTs = uint32(block.timestamp);
        uint256 nonce = 1;
        bytes32 contentHash = keccak256(
            abi.encodePacked(templateId, openingTs, question)
        );
        bytes32 questionId = keccak256(
            abi.encodePacked(
                contentHash,
                address(arbitrator),
                uint32(300), // timeout,
                minBond,
                address(realitio),
                address(this),
                nonce
            )
        );

        vm.mockCall(
            realitio,
            abi.encodeWithSelector(
                IRealityETH.notifyOfArbitrationRequest.selector,
                questionId,
                address(this),
                maxPrevious
            ),
            abi.encode()
        );

        vm.deal(address(this), 1 ether);
        arbitrator.requestArbitration{value: 1 ether}(questionId, maxPrevious);

        // Simulate passage of time
        vm.warp(block.timestamp + delay + 1);
        vm.mockCall(
            chainInfo,
            abi.encodeWithSelector(L2ChainInfo.getForkFee.selector),
            abi.encode(1)
        );
        vm.mockCall(
            chainInfo,
            abi.encodeWithSelector(bytes4(keccak256("l2Bridge()"))),
            abi.encode(address(0x1654))
        );
        vm.mockCall(
            address(0x1654), // l2 bridge contract
            abi.encodeWithSelector(bytes4(keccak256("bridgeAsset()"))),
            abi.encode()
        );
        vm.mockCall(
            chainInfo,
            abi.encodeWithSelector(bytes4(keccak256("getForkonomicToken()"))),
            abi.encode(address(0x16542))
        );
        vm.mockCall(
            address(this),
            abi.encodeWithSelector(
                bytes4(keccak256("getInvestigationDelay()"))
            ),
            abi.encode(delay)
        );
        vm.deal(address(arbitrator), 1 ether);
        arbitrator.requestActivateFork(
            templateId,
            openingTs,
            question,
            300, // timeout,
            minBond,
            nonce,
            address(this)
        );

        // Simulate a cancellation
        vm.mockCall(
            chainInfo,
            abi.encodeWithSelector(bytes4(keccak256("l2Bridge()"))),
            abi.encode(address(this))
        );
        vm.deal(address(this), 1 ether);
        arbitrator.onMessageReceived{value: 1 ether}(
            address(l1GlobalForkRequester),
            0,
            abi.encode(questionId)
        );

        vm.deal(address(this), 1 ether);
        uint256 nextTimestamp = block.timestamp + 1;
        vm.warp(nextTimestamp);
        arbitrator.requestArbitration{value: 1 ether}(questionId, maxPrevious);
        // now the requestArbitationFork can be called immediately, without waiting for the delay
        vm.mockCall(
            chainInfo,
            abi.encodeWithSelector(L2ChainInfo.getForkFee.selector),
            abi.encode(1)
        );
        vm.mockCall(
            chainInfo,
            abi.encodeWithSelector(bytes4(keccak256("l2Bridge()"))),
            abi.encode(address(0x1654))
        );
        vm.mockCall(
            address(0x1654), // l2 bridge contract
            abi.encodeWithSelector(bytes4(keccak256("bridgeAsset()"))),
            abi.encode()
        );
        vm.mockCall(
            chainInfo,
            abi.encodeWithSelector(bytes4(keccak256("getForkonomicToken()"))),
            abi.encode(address(0x16542))
        );
        vm.mockCall(
            address(this),
            abi.encodeWithSelector(
                bytes4(keccak256("getInvestigationDelay()"))
            ),
            abi.encode(delay)
        );
        vm.deal(address(arbitrator), 1 ether);
        arbitrator.requestActivateFork(
            templateId,
            openingTs,
            question,
            300, // timeout,
            minBond,
            nonce,
            address(this)
        );
    }

    function testTopUpArbitrationRequest() public {
        bytes32 questionId = keccak256("testQuestion");
        uint256 maxPrevious = 0;
        uint256 arbitrationFee = arbitrator.getDisputeFee(questionId);

        // Mock call to realitio and simulate arbitration request
        vm.mockCall(
            address(realitio),
            abi.encodeWithSelector(
                IRealityETH.notifyOfArbitrationRequest.selector,
                questionId,
                address(this),
                maxPrevious
            ),
            abi.encode()
        );

        vm.deal(address(this), arbitrationFee);
        arbitrator.requestArbitration{value: arbitrationFee}(
            questionId,
            maxPrevious
        );

        // Top up the arbitration request
        uint256 topUpAmount = 0.5 ether;
        vm.deal(address(this), topUpAmount);
        arbitrator.topUpArbitrationRequest{value: topUpAmount}(questionId);

        // Verify the top-up was successful
        (, , uint256 paid, , ) = arbitrator.arbitrationRequests(questionId);
        assertEq(
            paid,
            arbitrationFee + topUpAmount,
            "Top-up amount not added to the paid total"
        );

        // Test for non-existent arbitration request
        bytes32 invalidQuestionId = keccak256("invalidQuestion");
        vm.expectRevert(IL2ForkArbitrator.ArbitrationDataNotSet.selector);
        vm.deal(address(this), topUpAmount);
        arbitrator.topUpArbitrationRequest{value: topUpAmount}(
            invalidQuestionId
        );
    }
}
