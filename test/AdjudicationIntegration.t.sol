pragma solidity ^0.8.20;
import {Test} from "forge-std/Test.sol";
import {Arbitrator} from "../contracts/lib/reality-eth/Arbitrator.sol";

// TODO: Replace this with whatever zkEVM or whatever platform we're on uses
import {IAMB} from "../contracts/interfaces/IAMB.sol";

import {IRealityETH} from "../contracts/interfaces/IRealityETH.sol";
import {IERC20} from "../contracts/interfaces/IERC20.sol";
import {ForkableRealityETH_ERC20} from "../contracts/ForkableRealityETH_ERC20.sol";
import {RealityETH_v3_0} from "../contracts/lib/reality-eth/RealityETH-3.0.sol";
import {AdjudicationFramework} from "../contracts/AdjudicationFramework.sol";

import {L2ForkArbitrator} from "../contracts/L2ForkArbitrator.sol";
import {L1GlobalRouter} from "../contracts/L1GlobalRouter.sol";
import {L2ChainInfo} from "../contracts/L2ChainInfo.sol";

import {MockPolygonZkEVMBridge} from "./testcontract/MockPolygonZkEVMBridge.sol";

contract AdjudicationIntegrationTest is Test {
    Arbitrator public govArb;

    IERC20 internal tokenMock = IERC20(0x1234567890123456789012345678901234567890);

    ForkableRealityETH_ERC20 internal l1realityEth;
    RealityETH_v3_0 internal l2realityEth;

    bytes32 internal addArbitratorQID1;
    bytes32 internal addArbitratorQID2;
    bytes32 internal removeArbitratorQID1;
    bytes32 internal removeArbitratorQID2;
    bytes32 internal upgradePropQID1;
    bytes32 internal upgradePropQID2;

    AdjudicationFramework internal adjudicationFramework1;
    AdjudicationFramework internal adjudicationFramework2;

    L2ForkArbitrator internal l2forkArbitrator;
    L2ChainInfo internal l2ChainInfo;

    Arbitrator internal l2Arbitrator1;
    Arbitrator internal l2Arbitrator2;

    address internal removeArbitrator1 = address(0xbabe05);
    address internal removeArbitrator2 = address(0xbabe06);

    address internal newForkManager1 = address(0xbabe07);
    address internal newForkManager2 = address(0xbabe08);

    address payable internal user1 = payable(address(0xbabe09));
    address payable internal user2 = payable(address(0xbabe10));

    string internal QUESTION_DELIM = "\u241f";

    /*
    Flow: 
        - Add/remove arbitrator are requested via the bridge by an AdjudicationFramework on L2.
        - Upgrade contracts are requested directly on L1, since L2 may be censored or non-functional.

    TODO: Consider whether we should gate the realityeth instance to approved AdjudicationFramework contracts (via bridge) and an upgrade manager contract.
    */

    uint32 constant REALITY_ETH_TIMEOUT = 86400;

    // Dummy addresses for things we message on l1
    // The following should be the same on all forks
    MockPolygonZkEVMBridge l2Bridge;
    address l1GlobalRouter = address(0xbabe12);

    // The following will change when we fork so we fake multiple versions here
    address l1ForkingManager = address(0xbabe13);
    address l1Token = address(0xbabe14);

    address l1ForkingManagerF1 = address(0x1abe13);
    address l1TokenF1 = address(0x1abe14);

    address l1ForkingManagerF2 = address(0x2abe13);
    address l1TokenF2 = address(0x2abe14);

    uint32 l1chainId = 1;

    uint256 forkingFee = 5000; // Should ultimately come from l1 forkingmanager

    function setUp() public {

        l2Bridge = new MockPolygonZkEVMBridge();

        // For now the values of the l1 contracts are all made up
        // Ultimately our tests should include a deployment on l1
        l2ChainInfo = new L2ChainInfo(l1chainId, address(l2Bridge), l1GlobalRouter);

        // Pretend to send the initial setup to the l2 directory via the bridge
        // Triggers:
        // l2ChainInfo.onMessageReceived(l1GlobalRouter, l1chainId, fakeMessageData);
        // In reality this would originate on L1.
        bytes memory fakeMessageData = abi.encode(address(l1ForkingManager), address(l1Token), uint256(forkingFee), bytes32(0x0), bytes32(0x0));
        l2Bridge.fakeClaimMessage(address(l1GlobalRouter), uint32(l1chainId), address(l2ChainInfo), fakeMessageData, uint256(0));

        l1realityEth = new ForkableRealityETH_ERC20();
        l1realityEth.init(tokenMock, address(0), bytes32(0));

        /*
        Creates templates 1, 2, 3 as
        TODO: These should probably be special values, or at least not conflict with the standard in-built ones
        1: '{"title": "Should we add arbitrator %s to whitelist contract %s", "type": "bool"}'
        2: '{"title": "Should we remove arbitrator %s from whitelist contract %s", "type": "bool"}'
        3: '{"title": "Should switch to ForkManager %s", "type": "bool"}'
        */

        // Should be a governance arbitrator for adjudicating upgrades
        govArb = new Arbitrator();
        govArb.setRealitio(address(l1realityEth));
        govArb.setDisputeFee(50);

        user1.transfer(1000000);
        user2.transfer(1000000);

        // NB we're modelling this on the same chain but it should really be the l2
        l2realityEth = new RealityETH_v3_0();

        l2forkArbitrator = new L2ForkArbitrator(IRealityETH(l2realityEth), L2ChainInfo(l2ChainInfo), L1GlobalRouter(l1GlobalRouter), forkingFee);

        // TODO: Make it possible to pass initial arbitrators in the constructor
        // address arbAddr = address(l2Arbitrator1);
        // address[] memory initialArbs;
        // initialArbs[0] = arbAddr;

        // The adjudication framework can act like a regular reality.eth arbitrator.
        // It will also use reality.eth to arbitrate its own governance, using the L2ForkArbitrator which makes L1 fork requests.
        adjudicationFramework1 = new AdjudicationFramework(address(l2realityEth), 123, address(l2forkArbitrator));

        l2Arbitrator1 = new Arbitrator();
        // NB The adjudication framework looks to individual arbitrators like a reality.eth question, so they can use it without being changed.
        l2Arbitrator1.setRealitio(address(adjudicationFramework1));
        l2Arbitrator1.setDisputeFee(50);

        // Set up another idential arbitrator but don't add them to the framework yet.
        l2Arbitrator2 = new Arbitrator();
        l2Arbitrator2.setRealitio(address(adjudicationFramework1));
        l2Arbitrator2.setDisputeFee(50);

        // Create a question - from beginAddArbitratorToWhitelist
        // For the setup we'll do this as an uncontested addition.
        // Contested cases should also be tested.

        addArbitratorQID1 = adjudicationFramework1.beginAddArbitratorToAllowList(address(l2Arbitrator1));
        l2realityEth.submitAnswer{value: 10000}(addArbitratorQID1, bytes32(uint256(1)), 0);

        uint32 to = l2realityEth.getTimeout(addArbitratorQID1);
        assertEq(to, REALITY_ETH_TIMEOUT);

        uint32 finalizeTs = l2realityEth.getFinalizeTS(addArbitratorQID1);
        assertTrue(finalizeTs > block.timestamp, "finalization ts should be passed block ts");
        
        vm.expectRevert("question must be finalized");
        bytes32 r = l2realityEth.resultFor(addArbitratorQID1);
        assertTrue(finalizeTs > block.timestamp, "finalization ts should be passed block ts");

        vm.expectRevert("question must be finalized");
        adjudicationFramework1.executeAddArbitratorToAllowList(addArbitratorQID1);

        skip(86401);
        adjudicationFramework1.executeAddArbitratorToAllowList(addArbitratorQID1);

        assertTrue(adjudicationFramework1.arbitrators(address(l2Arbitrator1)));

    }

    function testContestedAddArbitrator()
    internal {

        addArbitratorQID2 = adjudicationFramework1.beginAddArbitratorToAllowList(address(l2Arbitrator2));
        l2realityEth.submitAnswer{value: 10000}(addArbitratorQID2, bytes32(uint256(1)), 0);
        l2realityEth.submitAnswer{value: 20000}(addArbitratorQID2, bytes32(uint256(0)), 0);

        l2forkArbitrator.requestArbitration(addArbitratorQID2, 0);

    }

    function _setupContestableQuestion() 
    internal returns (bytes32) {

        // ask a question
        bytes32 qid = l2realityEth.askQuestion(0, "Question 1", address(adjudicationFramework1), 123, uint32(block.timestamp), 0);

        // do some bond escalation
        vm.prank(user1);
        l2realityEth.submitAnswer{value: 10}(qid, bytes32(uint256(1)), 0);
        vm.prank(user2);
        l2realityEth.submitAnswer{value: 20}(qid, bytes32(0), 0);

        return qid;

    }

    function _setupArbitratedQuestion(bytes32 question_id) 
    internal {

        // request adjudication from the framework
        vm.prank(user1);
        assertTrue(adjudicationFramework1.requestArbitration{value: 500000}(question_id, 0));

        vm.expectRevert("Arbitrator must be on the allowlist");
        l2Arbitrator2.requestArbitration{value: 500000}(question_id, 0);

    }

    function testL2RequestQuestionArbitration() public {

        bytes32 qid = _setupContestableQuestion();
        _setupArbitratedQuestion(qid);

        // permitted arbitrator grabs the question off the queue and locks it so nobody else can get it
        assertTrue(l2Arbitrator1.requestArbitration{value: 500000}(qid, 0));
        l2Arbitrator1.submitAnswerByArbitrator(qid, bytes32(uint256(1)), user1);

        vm.expectRevert("Challenge deadline must have passed");
        adjudicationFramework1.completeArbitration(qid, bytes32(uint256(1)), user1);
        
        skip(86401);
        adjudicationFramework1.completeArbitration(qid, bytes32(uint256(1)), user1);

        assertEq(l2realityEth.resultFor(qid), bytes32(uint256(1)), "reality.eth question should be settled");

    }

    function _setupContestedArbitration() internal returns (bytes32 questionId, bytes32 removalQuestionId, bytes32 lastHistoryHash, bytes32 lastAnswer, address lastAnswerer) {

        bytes32 qid = _setupContestableQuestion();
        _setupArbitratedQuestion(qid);

        // TODO: Separate this part out to reuse in different tests for uncontested freeze and fork?  
        // permitted arbitrator grabs the question off the queue and locks it so nobody else can get it
        assertTrue(l2Arbitrator1.requestArbitration{value: 500000}(qid, 0));
        l2Arbitrator1.submitAnswerByArbitrator(qid, bytes32(uint256(1)), user1);

        vm.expectRevert("Challenge deadline must have passed");
        adjudicationFramework1.completeArbitration(qid, bytes32(uint256(1)), user1);

        // now before we can complete this somebody challenges it
        bytes32 removalQuestionId = adjudicationFramework1.beginRemoveArbitratorFromAllowList(address(l2Arbitrator1));

        vm.expectRevert("Bond too low to freeze");
        adjudicationFramework1.freezeArbitrator(removalQuestionId);

        bytes32 lastHistoryHash = l2realityEth.getHistoryHash(removalQuestionId);
        vm.prank(user2);
        l2realityEth.submitAnswer{value: 20000}(removalQuestionId, bytes32(uint256(1)), 0);
        adjudicationFramework1.freezeArbitrator(removalQuestionId);
        assertEq(adjudicationFramework1.countArbitratorFreezePropositions(address(l2Arbitrator1)), uint256(1));

        //skip(86401);
        //vm.expectRevert("Arbitrator must not be under dispute");
        //adjudicationFramework1.completeArbitration(qid, bytes32(uint256(1)), user1);

        /* Next step
            a) Make a governance proposition on L1, escalating to a fork
            b) Make a direct fork request on L1 via the bridge
            c) Make a fork request on L2, get the response via the bridge
        */

        return (qid, removalQuestionId, lastHistoryHash, bytes32(uint256(1)), user2);

    }

    function testArbitrationContestPassedWithoutFork() public {

        (bytes32 qid, bytes32 removalQuestionId, bytes32 lastHistoryHash, bytes32 lastAnswer, address lastAnswerer) = _setupContestedArbitration();

        // Currently in the "yes" state, so once it times out we can complete the removal 

        // Now wait for the timeout and settle the proposition
        vm.expectRevert("question must be finalized");
        bytes32 result = l2realityEth.resultFor(removalQuestionId);

        vm.expectRevert("question must be finalized");
        adjudicationFramework1.executeRemoveArbitratorFromAllowList(removalQuestionId);

        skip(86401);

        adjudicationFramework1.executeRemoveArbitratorFromAllowList(removalQuestionId);

    }

    function testArbitrationContestRejectedWithoutFork() public {

        (bytes32 qid, bytes32 removalQuestionId, bytes32 lastHistoryHash, bytes32 lastAnswer, address lastAnswerer) = _setupContestedArbitration();

        // Put the proposition to remove the arbitrator into the "no" state
        l2realityEth.submitAnswer{value: 40000}(removalQuestionId, bytes32(uint256(0)), 0);

        // Now wait for the timeout and settle the proposition

        vm.expectRevert("question must be finalized");
        bytes32 result = l2realityEth.resultFor(removalQuestionId);

        vm.expectRevert("question must be finalized");
        adjudicationFramework1.executeRemoveArbitratorFromAllowList(removalQuestionId);

        skip(86401);

        vm.expectRevert("Result was not 1");
        adjudicationFramework1.executeRemoveArbitratorFromAllowList(removalQuestionId);

        assertEq(adjudicationFramework1.countArbitratorFreezePropositions(address(l2Arbitrator1)), uint256(1));
        adjudicationFramework1.clearFailedProposition(removalQuestionId);
        assertEq(adjudicationFramework1.countArbitratorFreezePropositions(address(l2Arbitrator1)), uint256(0));

    }

    function testArbitrationContestPassedWithFork() public {

        (bytes32 qid, bytes32 removalQuestionId, bytes32 lastHistoryHash, bytes32 lastAnswer, address lastAnswerer) = _setupContestedArbitration();

        // Currently in the "yes" state, so once it times out we can complete the removal 

        // Now wait for the timeout and settle the proposition
        vm.expectRevert("question must be finalized");
        bytes32 result = l2realityEth.resultFor(removalQuestionId);

        assertEq(address(l2forkArbitrator.realitio()), address(l2realityEth), "l2forkArbitrator expects to arbitrate our l2realityEth");
        assertEq(address(adjudicationFramework1.realityETH()), address(l2realityEth), "adjudicationFramework1 expects to use our l2realityEth");
        assertEq(address(l2forkArbitrator), l2realityEth.getArbitrator(removalQuestionId), "Arbitrator of the removalQuestionId is l2forkArbitrator");

        uint256 forkFee = l2forkArbitrator.getDisputeFee(removalQuestionId);
        l2forkArbitrator.requestArbitration{value: forkFee}(removalQuestionId, 0);

        // IMAGINE THE FORK HAPPENED HERE
        // There are now two L2s, each with a different chain ID
        uint256 newChainId1 = 123;
        vm.chainId(newChainId1);

        // TODO: Adjust the forkingFee as the total supply has changed a bit
        bytes memory fakeMessageData = abi.encode(address(l1ForkingManagerF1), address(l1TokenF1), uint256(forkingFee), removalQuestionId, bytes32(uint256(1)));
        l2Bridge.fakeClaimMessage(address(l1GlobalRouter), uint32(l1chainId), address(l2ChainInfo), fakeMessageData, uint256(0));

        assertTrue(l2realityEth.isPendingArbitration(removalQuestionId));
        l2forkArbitrator.handleCompletedFork(removalQuestionId, lastHistoryHash, lastAnswer, lastAnswerer);

        assertFalse(l2realityEth.isPendingArbitration(removalQuestionId));

        assertEq(adjudicationFramework1.countArbitratorFreezePropositions(address(l2Arbitrator1)), 1);
        assertTrue(adjudicationFramework1.arbitrators(address(l2Arbitrator1)));
        adjudicationFramework1.executeRemoveArbitratorFromAllowList(removalQuestionId);
        assertFalse(adjudicationFramework1.arbitrators(address(l2Arbitrator1)));
        assertEq(adjudicationFramework1.countArbitratorFreezePropositions(address(l2Arbitrator1)), 0);

        // TODO: Retry the arbitration with a new arbitrator

    }

    function testArbitrationContestRejectedWithFork() public {

        (bytes32 qid, bytes32 removalQuestionId, bytes32 lastHistoryHash, bytes32 lastAnswer, address lastAnswerer) = _setupContestedArbitration();

        // Currently in the "yes" state, so once it times out we can complete the removal 

        // Now wait for the timeout and settle the proposition
        vm.expectRevert("question must be finalized");
        bytes32 result = l2realityEth.resultFor(removalQuestionId);

        assertEq(address(l2forkArbitrator.realitio()), address(l2realityEth), "l2forkArbitrator expects to arbitrate our l2realityEth");
        assertEq(address(adjudicationFramework1.realityETH()), address(l2realityEth), "adjudicationFramework1 expects to use our l2realityEth");
        assertEq(address(l2forkArbitrator), l2realityEth.getArbitrator(removalQuestionId), "Arbitrator of the removalQuestionId is l2forkArbitrator");

        uint256 forkFee = l2forkArbitrator.getDisputeFee(removalQuestionId);
        l2forkArbitrator.requestArbitration{value: forkFee}(removalQuestionId, 0);

        // IMAGINE THE FORK HAPPENED HERE
        // There are now two L2s, each with a different chain ID
        uint256 newChainId1 = 124;
        vm.chainId(newChainId1);

        // TODO: Adjust the forkingFee as the total supply has changed a bit
        bytes memory fakeMessageData = abi.encode(address(l1ForkingManagerF1), address(l1TokenF1), uint256(forkingFee), removalQuestionId, bytes32(uint256(0)));
        l2Bridge.fakeClaimMessage(address(l1GlobalRouter), uint32(l1chainId), address(l2ChainInfo), fakeMessageData, uint256(0));

        assertTrue(l2realityEth.isPendingArbitration(removalQuestionId));
        l2forkArbitrator.handleCompletedFork(removalQuestionId, lastHistoryHash, lastAnswer, lastAnswerer);

        assertFalse(l2realityEth.isPendingArbitration(removalQuestionId));

        assertEq(adjudicationFramework1.countArbitratorFreezePropositions(address(l2Arbitrator1)), 1);
        assertTrue(adjudicationFramework1.arbitrators(address(l2Arbitrator1)));

        vm.expectRevert("Result was not 1");
        adjudicationFramework1.executeRemoveArbitratorFromAllowList(removalQuestionId);

        adjudicationFramework1.clearFailedProposition(removalQuestionId);

        assertTrue(adjudicationFramework1.arbitrators(address(l2Arbitrator1)));
        assertEq(adjudicationFramework1.countArbitratorFreezePropositions(address(l2Arbitrator1)), 0);

    }


    /*
    // TODO:
    If the fork failed because the fee changed or something else forked first (does this happen???), we may need to clearFailedForkAttempt()
    function testArbitrationContestForkFailed() public {

    }
    */

    /*
    function testL1RequestGovernanceArbitration() public {
        bytes32 questionId = keccak256(abi.encodePacked("Question 1")); // TODO: This should be in some wrapper contract
        govArb.setDisputeFee(50);
        vm.mockCall(
            address(l1realityEth),
            abi.encodeWithSelector(IRealityETH.isFinalized.selector),
            abi.encode(true)
        );
        assertTrue(govArb.requestArbitration{value: 50}(questionId, 0));
        assertEq(govArb.arbitration_bounties(questionId), 50);
    }
    */


}
