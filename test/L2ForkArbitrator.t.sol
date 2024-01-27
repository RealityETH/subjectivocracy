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

    function testStoreInformation() public {
        uint256 delay = 60 * 60; // 1 hour
        uint256 templateId = 1;
        string memory question = "TestQuestion";
        uint32 timeout = 300;
        uint256 minBond = 1 ether;
        uint32 openingTs = uint32(block.timestamp);
        uint256 nonce = 1;
        arbitrator.storeInformation(
            templateId,
            openingTs,
            question,
            timeout,
            minBond,
            nonce,
            delay
        );

        bytes32 contentHash = keccak256(
            abi.encodePacked(templateId, openingTs, question)
        );
        bytes32 questionId = keccak256(
            abi.encodePacked(
                contentHash,
                address(arbitrator),
                timeout,
                minBond,
                address(realitio),
                address(this),
                nonce
            )
        );

        (, uint256 storedDelay) = arbitrator.arbitrationData(questionId);
        assertEq(storedDelay, delay, "Stored delay is incorrect");
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
        vm.expectRevert(IL2ForkArbitrator.ArbitrationDataNotSet.selector);
        arbitrator.requestActivateFork(questionId);

        // setup the necessary conditions
        arbitrator.storeInformation(
            templateId,
            openingTs,
            question,
            300, // timeout,
            minBond,
            nonce,
            delay
        );

        // Attempt to activate fork
        vm.expectRevert(IL2ForkArbitrator.RequestStillInWaitingPeriod.selector);
        arbitrator.requestActivateFork(questionId);

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
        arbitrator.requestActivateFork(questionId);
    }

    function testAnyoneCanRequestForkAfterACancellation() public {
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

        // setup the necessary conditions
        arbitrator.storeInformation(
            templateId,
            openingTs,
            question,
            300, // timeout,
            minBond,
            nonce,
            delay
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
        arbitrator.requestActivateFork(questionId);

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

        // not everyone can immediately call requestActivateFork
        vm.mockCall(
            chainInfo,
            abi.encodeWithSelector(bytes4(keccak256("l2Bridge()"))),
            abi.encode(address(0x1654))
        );
        vm.expectRevert(IL2ForkArbitrator.WrongSender.selector);
        vm.prank(address(0x123));
        arbitrator.requestActivateFork(questionId);

        vm.warp(block.timestamp + arbitrator.delayForForkInitiator() + 1);

        // After waiting some time, it is possible for anyone to call requestActivateFork
        vm.prank(address(0x123));
        arbitrator.requestActivateFork(questionId);
    }
}
