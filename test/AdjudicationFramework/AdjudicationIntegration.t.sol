pragma solidity ^0.8.20;

/* solhint-disable not-rely-on-time */
/* solhint-disable reentrancy */
/* solhint-disable quotes */

import {Vm} from "forge-std/Vm.sol";

import {Test} from "forge-std/Test.sol";
import {Arbitrator} from "../../contracts/lib/reality-eth/Arbitrator.sol";

import {IRealityETH} from "../../contracts/lib/reality-eth/interfaces/IRealityETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ForkableRealityETH_ERC20} from "../../contracts/ForkableRealityETH_ERC20.sol";
import {RealityETH_v3_0} from "../../contracts/lib/reality-eth/RealityETH-3.0.sol";
import {AdjudicationFramework} from "../../contracts/AdjudicationFramework/AdjudicationFrameworkForRequestsWithChallengeManagement.sol";

import {L2ForkArbitrator} from "../../contracts/L2ForkArbitrator.sol";
import {L1GlobalChainInfoPublisher} from "../../contracts/L1GlobalChainInfoPublisher.sol";
import {L1GlobalForkRequester} from "../../contracts/L1GlobalForkRequester.sol";
import {L2ChainInfo} from "../../contracts/L2ChainInfo.sol";

import {MockPolygonZkEVMBridge} from "../testcontract/MockPolygonZkEVMBridge.sol";
import {MinimalAdjudicationFramework} from "../../contracts/AdjudicationFramework/MinimalAdjudicationFramework.sol";

contract AdjudicationIntegrationTest is Test {
    Arbitrator public govArb;

    IERC20 internal tokenMock =
        IERC20(0x1234567890123456789012345678901234567890);

    ForkableRealityETH_ERC20 internal l1RealityEth;
    RealityETH_v3_0 internal l2RealityEth;

    bytes32 internal addArbitratorQID1;
    bytes32 internal addArbitratorQID2;
    bytes32 internal removeArbitratorQID1;
    bytes32 internal removeArbitratorQID2;
    bytes32 internal upgradePropQID1;
    bytes32 internal upgradePropQID2;

    AdjudicationFramework internal adjudicationFramework1;
    AdjudicationFramework internal adjudicationFramework2;

    L2ForkArbitrator internal l2ForkArbitrator;
    L2ChainInfo internal l2ChainInfo;

    Arbitrator internal l2Arbitrator1;
    Arbitrator internal l2Arbitrator2;

    address internal initialArbitrator1 = address(0xbeeb01);
    address internal initialArbitrator2 = address(0xbeeb02);

    address internal removeArbitrator1 = address(0xbabe05);
    address internal removeArbitrator2 = address(0xbabe06);

    address internal newForkManager1 = address(0xbabe07);
    address internal newForkManager2 = address(0xbabe08);

    address payable internal user1 = payable(address(0xbabe09));
    address payable internal user2 = payable(address(0xbabe10));

    // We'll use a different address to deploy AdjudicationFramework because we want to logs with its address in
    address payable internal adjudictionDeployer = payable(address(0xbabe11));

    string internal constant QUESTION_DELIM = "\u241f";

    /*
    Flow: 
        - Add/remove arbitrator are requested via the bridge by an AdjudicationFramework on L2.
        - Upgrade contracts are requested directly on L1, since L2 may be censored or non-functional.

    TODO: Consider whether we should gate the realityeth instance to approved AdjudicationFramework contracts (via bridge) and an upgrade manager contract.
    */

    uint32 internal constant REALITY_ETH_TIMEOUT = 86400;

    // Dummy addresses for things we message on l1
    // The following should be the same on all forks
    MockPolygonZkEVMBridge internal l2Bridge;
    address internal l1GlobalForkRequester =
        address(new L1GlobalForkRequester());
    address internal l1GlobalChainInfoPublisher = address(0xbabe12);

    // The following will change when we fork so we fake multiple versions here
    address internal l1ForkingManager = address(0xbabe13);
    address internal l1Token = address(0xbabe14);

    address internal l1ForkingManagerF1 = address(0x1abe13);
    address internal l1TokenF1 = address(0x1abe14);

    address internal l1ForkingManagerF2 = address(0x2abe13);
    address internal l1TokenF2 = address(0x2abe14);

    uint64 internal l2ChainIdInit = 1;

    uint256 internal forkingFee = 5000; // Should ultimately come from l1 forkingmanager

    function setUp() public {
        l2Bridge = new MockPolygonZkEVMBridge();

        // For now the values of the l1 contracts are all made up
        // Ultimately our tests should include a deployment on l1
        l2ChainInfo = new L2ChainInfo(
            address(l2Bridge),
            l1GlobalChainInfoPublisher
        );

        // Pretend to send the initial setup to the l2 directory via the bridge
        // Triggers:
        // l2ChainInfo.onMessageReceived(l1GlobalChainInfoPublisher, l1ChainId, fakeMessageData);
        // In reality this would originate on L1.
        vm.chainId(l2ChainIdInit);
        bytes memory fakeMessageData = abi.encode(
            l2ChainIdInit,
            address(l1ForkingManager),
            uint256(forkingFee),
            false,
            address(l2ForkArbitrator),
            bytes32(0x0),
            bytes32(0x0)
        );
        l2Bridge.fakeClaimMessage(
            address(l1GlobalChainInfoPublisher),
            uint32(0),
            address(l2ChainInfo),
            fakeMessageData,
            uint256(0)
        );

        l1RealityEth = new ForkableRealityETH_ERC20();
        l1RealityEth.init(tokenMock, address(0), bytes32(0));

        /*
        Creates templates 1, 2, 3 as
        TODO: These should probably be special values, or at least not conflict with the standard in-built ones
        1: '{"title": "Should we add arbitrator %s to whitelist contract %s", "type": "bool"}'
        2: '{"title": "Should we remove arbitrator %s from whitelist contract %s", "type": "bool"}'
        3: '{"title": "Should switch to ForkManager %s", "type": "bool"}'
        */

        // Should be a governance arbitrator for adjudicating upgrades
        govArb = new Arbitrator();
        govArb.setRealitio(address(l1RealityEth));
        govArb.setDisputeFee(50);

        user1.transfer(1000000);
        user2.transfer(1000000);

        // NB we're modelling this on the same chain but it should really be the l2
        l2RealityEth = new RealityETH_v3_0();

        l2ForkArbitrator = new L2ForkArbitrator(
            IRealityETH(l2RealityEth),
            L2ChainInfo(l2ChainInfo),
            L1GlobalForkRequester(l1GlobalForkRequester),
            forkingFee
        );

        // The adjudication framework can act like a regular reality.eth arbitrator.
        // It will also use reality.eth to arbitrate its own governance, using the L2ForkArbitrator which makes L1 fork requests.
        address[] memory initialArbitrators = new address[](2);
        initialArbitrators[0] = initialArbitrator1;
        initialArbitrators[1] = initialArbitrator2;
        vm.prank(adjudictionDeployer);
        adjudicationFramework1 = new AdjudicationFramework(
            address(l2RealityEth),
            123,
            address(l2ForkArbitrator),
            initialArbitrators
        );

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

        addArbitratorQID1 = adjudicationFramework1
            .beginAddArbitratorToAllowList(address(l2Arbitrator1));
        l2RealityEth.submitAnswer{value: 10000}(
            addArbitratorQID1,
            bytes32(uint256(1)),
            0
        );

        uint32 to = l2RealityEth.getTimeout(addArbitratorQID1);
        assertEq(to, REALITY_ETH_TIMEOUT);

        uint32 finalizeTs = l2RealityEth.getFinalizeTS(addArbitratorQID1);
        assertTrue(
            finalizeTs > block.timestamp,
            "finalization ts should be passed block ts"
        );

        vm.expectRevert("question must be finalized");
        l2RealityEth.resultFor(addArbitratorQID1);
        assertTrue(
            finalizeTs > block.timestamp,
            "finalization ts should be passed block ts"
        );

        vm.expectRevert("question must be finalized");
        adjudicationFramework1.executeAddArbitratorToAllowList(
            addArbitratorQID1
        );

        skip(86401);
        adjudicationFramework1.executeAddArbitratorToAllowList(
            addArbitratorQID1
        );

        assertTrue(adjudicationFramework1.contains(address(l2Arbitrator1)));
    }

    function testInitialArbitrators() public {
        // Initial arbitrators from the contructor should be added
        assertTrue(adjudicationFramework1.contains(initialArbitrator1));
        assertTrue(adjudicationFramework1.contains(initialArbitrator2));
        // This arbitrator may be added in other tests by creating a proposition
        assertFalse(adjudicationFramework1.contains(address(l2Arbitrator2)));
    }

    function testContestedAddArbitrator() public {
        addArbitratorQID2 = adjudicationFramework1
            .beginAddArbitratorToAllowList(address(l2Arbitrator2));
        l2RealityEth.submitAnswer{value: 10000}(
            addArbitratorQID2,
            bytes32(uint256(1)),
            0
        );
        l2RealityEth.submitAnswer{value: 20000}(
            addArbitratorQID2,
            bytes32(uint256(0)),
            0
        );

        l2ForkArbitrator.requestArbitration{value: 500000}(
            addArbitratorQID2,
            0
        );

        // This talks to the bridge, we fake what happens next.
        // TODO: Hook this up to the real bridge so we can test it properly.
    }

    function _setupContestableQuestion() internal returns (bytes32) {
        // ask a question
        bytes32 qid = l2RealityEth.askQuestion(
            0,
            "Question 1",
            address(adjudicationFramework1),
            123,
            uint32(block.timestamp),
            0
        );

        // do some bond escalation
        vm.prank(user1);
        l2RealityEth.submitAnswer{value: 10}(qid, bytes32(uint256(1)), 0);
        vm.prank(user2);
        l2RealityEth.submitAnswer{value: 20}(qid, bytes32(0), 0);

        return qid;
    }

    function _setupArbitratedQuestion(bytes32 questionId) internal {
        // request adjudication from the framework
        vm.prank(user1);
        assertTrue(
            adjudicationFramework1.requestArbitration{value: 500000}(
                questionId,
                0
            )
        );

        vm.expectRevert(
            MinimalAdjudicationFramework.OnlyAllowlistedActor.selector
        );
        l2Arbitrator2.requestArbitration{value: 500000}(questionId, 0);
    }

    function testL2RequestQuestionArbitration() public {
        bytes32 qid = _setupContestableQuestion();
        _setupArbitratedQuestion(qid);

        // permitted arbitrator grabs the question off the queue and locks it so nobody else can get it
        assertTrue(l2Arbitrator1.requestArbitration{value: 500000}(qid, 0));
        l2Arbitrator1.submitAnswerByArbitrator(qid, bytes32(uint256(1)), user1);

        vm.expectRevert("Challenge deadline not passed");
        adjudicationFramework1.completeArbitration(
            qid,
            bytes32(uint256(1)),
            user1
        );

        skip(86401);
        adjudicationFramework1.completeArbitration(
            qid,
            bytes32(uint256(1)),
            user1
        );

        assertEq(
            l2RealityEth.resultFor(qid),
            bytes32(uint256(1)),
            "reality.eth question should be settled"
        );
    }

    function _setupContestedArbitration()
        internal
        returns (
            bytes32 questionId,
            bytes32 removalQuestionId,
            bytes32 lastHistoryHash,
            bytes32 lastAnswer,
            address lastAnswerer
        )
    {
        bytes32 qid = _setupContestableQuestion();
        _setupArbitratedQuestion(qid);

        // TODO: Separate this part out to reuse in different tests for uncontested freeze and fork?
        // permitted arbitrator grabs the question off the queue and locks it so nobody else can get it
        assertTrue(l2Arbitrator1.requestArbitration{value: 500000}(qid, 0));
        l2Arbitrator1.submitAnswerByArbitrator(qid, bytes32(uint256(1)), user1);

        vm.expectRevert("Challenge deadline not passed");
        adjudicationFramework1.completeArbitration(
            qid,
            bytes32(uint256(1)),
            user1
        );

        // now before we can complete this somebody challenges it
        removalQuestionId = adjudicationFramework1
            .beginReplaceArbitratorFromAllowList(
                address(l2Arbitrator1),
                address(0)
            );
        l2RealityEth.submitAnswer{value: 10000}(
            removalQuestionId,
            bytes32(uint256(1)),
            0
        );

        bytes32[] memory hashes;
        address[] memory users;
        uint256[] memory bonds;
        bytes32[] memory answers;

        vm.expectRevert("Bond too low to freeze");
        adjudicationFramework1.freezeArbitrator(
            removalQuestionId,
            hashes,
            users,
            bonds,
            answers
        );

        lastHistoryHash = l2RealityEth.getHistoryHash(removalQuestionId);
        vm.prank(user2);
        l2RealityEth.submitAnswer{value: 20000}(
            removalQuestionId,
            bytes32(uint256(1)),
            0
        );
        adjudicationFramework1.freezeArbitrator(
            removalQuestionId,
            hashes,
            users,
            bonds,
            answers
        );
        assertEq(
            adjudicationFramework1.countArbitratorFreezePropositions(
                address(l2Arbitrator1)
            ),
            uint256(1)
        );

        //skip(86401);
        //vm.expectRevert("Arbitrator must not be under dispute");
        //adjudicationFramework1.completeArbitration(qid, bytes32(uint256(1)), user1);

        /* Next step
            a) Make a governance proposition on L1, escalating to a fork
            b) Make a direct fork request on L1 via the bridge
            c) Make a fork request on L2, get the response via the bridge
        */

        return (
            qid,
            removalQuestionId,
            lastHistoryHash,
            bytes32(uint256(1)),
            user2
        );
    }

    function testArbitrationContestPassedWithoutFork() public {
        // (bytes32 qid, bytes32 removalQuestionId, bytes32 lastHistoryHash, bytes32 lastAnswer, address lastAnswerer) = _setupContestedArbitration();
        (, bytes32 removalQuestionId, , , ) = _setupContestedArbitration();

        // Currently in the "yes" state, so once it times out we can complete the removal

        // Now wait for the timeout and settle the proposition
        vm.expectRevert("question must be finalized");
        l2RealityEth.resultFor(removalQuestionId);

        vm.expectRevert("question must be finalized");
        adjudicationFramework1.executeReplacementArbitratorFromAllowList(
            removalQuestionId
        );

        skip(86401);

        adjudicationFramework1.executeReplacementArbitratorFromAllowList(
            removalQuestionId
        );
    }

    function testArbitrationContestRejectedWithoutFork() public {
        //(bytes32 qid, bytes32 removalQuestionId, bytes32 lastHistoryHash, bytes32 lastAnswer, address lastAnswerer) = _setupContestedArbitration();
        (, bytes32 removalQuestionId, , , ) = _setupContestedArbitration();

        // Put the proposition to remove the arbitrator into the "no" state
        l2RealityEth.submitAnswer{value: 40000}(
            removalQuestionId,
            bytes32(uint256(0)),
            0
        );

        // Now wait for the timeout and settle the proposition

        vm.expectRevert("question must be finalized");
        l2RealityEth.resultFor(removalQuestionId);

        vm.expectRevert("question must be finalized");
        adjudicationFramework1.executeReplacementArbitratorFromAllowList(
            removalQuestionId
        );

        skip(86401);

        vm.expectRevert("Result was not 1");
        adjudicationFramework1.executeReplacementArbitratorFromAllowList(
            removalQuestionId
        );

        assertEq(
            adjudicationFramework1.countArbitratorFreezePropositions(
                address(l2Arbitrator1)
            ),
            uint256(1)
        );
        adjudicationFramework1.clearFailedProposition(removalQuestionId);
        assertEq(
            adjudicationFramework1.countArbitratorFreezePropositions(
                address(l2Arbitrator1)
            ),
            uint256(0)
        );
    }

    function testArbitrationContestPassedWithFork() public {
        // (bytes32 qid, bytes32 removalQuestionId, bytes32 lastHistoryHash, bytes32 lastAnswer, address lastAnswerer) = _setupContestedArbitration();
        (
            ,
            bytes32 removalQuestionId,
            bytes32 lastHistoryHash,
            bytes32 lastAnswer,
            address lastAnswerer
        ) = _setupContestedArbitration();

        // Currently in the "yes" state, so once it times out we can complete the removal

        // Now wait for the timeout and settle the proposition
        vm.expectRevert("question must be finalized");
        l2RealityEth.resultFor(removalQuestionId);

        assertEq(
            address(l2ForkArbitrator.realitio()),
            address(l2RealityEth),
            "l2ForkArbitrator expects to arbitrate our l2RealityEth"
        );
        assertEq(
            address(adjudicationFramework1.realityETH()),
            address(l2RealityEth),
            "adjudicationFramework1 expects to use our l2RealityEth"
        );
        assertEq(
            address(l2ForkArbitrator),
            l2RealityEth.getArbitrator(removalQuestionId),
            "Arbitrator of the removalQuestionId is l2ForkArbitrator"
        );

        uint256 forkFee = l2ForkArbitrator.getDisputeFee(removalQuestionId);
        l2ForkArbitrator.requestArbitration{value: forkFee}(
            removalQuestionId,
            0
        );

        // IMAGINE THE FORK HAPPENED HERE
        // There are now two L2s, each with a different chain ID
        uint256 newChainId1 = 123;
        vm.chainId(newChainId1);

        // TODO: Adjust the forkingFee as the total supply has changed a bit
        bytes memory fakeMessageData = abi.encode(
            uint64(newChainId1),
            address(l1ForkingManagerF1),
            uint256(forkingFee),
            false,
            address(l2ForkArbitrator),
            removalQuestionId,
            bytes32(uint256(1))
        );
        l2Bridge.fakeClaimMessage(
            address(l1GlobalChainInfoPublisher),
            uint32(0),
            address(l2ChainInfo),
            fakeMessageData,
            uint256(0)
        );

        assertTrue(l2RealityEth.isPendingArbitration(removalQuestionId));
        l2ForkArbitrator.handleCompletedFork(
            removalQuestionId,
            lastHistoryHash,
            lastAnswer,
            lastAnswerer
        );

        assertFalse(l2RealityEth.isPendingArbitration(removalQuestionId));

        assertEq(
            adjudicationFramework1.countArbitratorFreezePropositions(
                address(l2Arbitrator1)
            ),
            1
        );
        assertTrue(adjudicationFramework1.contains(address(l2Arbitrator1)));
        adjudicationFramework1.executeReplacementArbitratorFromAllowList(
            removalQuestionId
        );
        assertFalse(adjudicationFramework1.contains(address(l2Arbitrator1)));
        assertEq(
            adjudicationFramework1.countArbitratorFreezePropositions(
                address(l2Arbitrator1)
            ),
            0,
            "count Arbitrator freeze propositions not correct"
        );

        // TODO: Retry the arbitration with a new arbitrator
    }

    function testArbitrationContestRejectedWithFork() public {
        //(bytes32 qid, bytes32 removalQuestionId, bytes32 lastHistoryHash, bytes32 lastAnswer, address lastAnswerer) = _setupContestedArbitration();
        (
            ,
            bytes32 removalQuestionId,
            bytes32 lastHistoryHash,
            bytes32 lastAnswer,
            address lastAnswerer
        ) = _setupContestedArbitration();

        // Currently in the "yes" state, so once it times out we can complete the removal

        // Now wait for the timeout and settle the proposition
        vm.expectRevert("question must be finalized");
        bytes32 result = l2RealityEth.resultFor(removalQuestionId);
        assertEq(result, bytes32(uint256(0)));

        assertEq(
            address(l2ForkArbitrator.realitio()),
            address(l2RealityEth),
            "l2ForkArbitrator expects to arbitrate our l2RealityEth"
        );
        assertEq(
            address(adjudicationFramework1.realityETH()),
            address(l2RealityEth),
            "adjudicationFramework1 expects to use our l2RealityEth"
        );
        assertEq(
            address(l2ForkArbitrator),
            l2RealityEth.getArbitrator(removalQuestionId),
            "Arbitrator of the removalQuestionId is l2ForkArbitrator"
        );

        uint256 forkFee = l2ForkArbitrator.getDisputeFee(removalQuestionId);
        l2ForkArbitrator.requestArbitration{value: forkFee}(
            removalQuestionId,
            0
        );

        // IMAGINE THE FORK HAPPENED HERE
        // There are now two L2s, each with a different chain ID
        uint256 newChainId1 = 124;
        vm.chainId(newChainId1);

        // TODO: Adjust the forkingFee as the total supply has changed a bit
        bytes memory fakeMessageData = abi.encode(
            uint64(newChainId1),
            address(l1ForkingManagerF1),
            uint256(forkingFee),
            false,
            address(l2ForkArbitrator),
            removalQuestionId,
            bytes32(uint256(0))
        );
        l2Bridge.fakeClaimMessage(
            address(l1GlobalChainInfoPublisher),
            uint32(0),
            address(l2ChainInfo),
            fakeMessageData,
            uint256(0)
        );

        assertTrue(l2RealityEth.isPendingArbitration(removalQuestionId));
        l2ForkArbitrator.handleCompletedFork(
            removalQuestionId,
            lastHistoryHash,
            lastAnswer,
            lastAnswerer
        );

        assertFalse(l2RealityEth.isPendingArbitration(removalQuestionId));

        assertEq(
            adjudicationFramework1.countArbitratorFreezePropositions(
                address(l2Arbitrator1)
            ),
            1
        );
        assertTrue(adjudicationFramework1.contains(address(l2Arbitrator1)));

        vm.expectRevert("Result was not 1");
        adjudicationFramework1.executeReplacementArbitratorFromAllowList(
            removalQuestionId
        );

        adjudicationFramework1.clearFailedProposition(removalQuestionId);

        assertTrue(adjudicationFramework1.contains(address(l2Arbitrator1)));
        assertEq(
            adjudicationFramework1.countArbitratorFreezePropositions(
                address(l2Arbitrator1)
            ),
            0
        );
    }

    function testArbitrationContestForkFailed() public {
        (, bytes32 removalQuestionId, , , ) = _setupContestedArbitration();

        // Currently in the "yes" state, so once it times out we can complete the removal

        // Now wait for the timeout and settle the proposition
        vm.expectRevert("question must be finalized");
        bytes32 result = l2RealityEth.resultFor(removalQuestionId);
        assertEq(result, bytes32(uint256(0)));

        assertEq(
            address(l2ForkArbitrator.realitio()),
            address(l2RealityEth),
            "l2ForkArbitrator expects to arbitrate our l2RealityEth"
        );
        assertEq(
            address(adjudicationFramework1.realityETH()),
            address(l2RealityEth),
            "adjudicationFramework1 expects to use our l2RealityEth"
        );
        assertEq(
            address(l2ForkArbitrator),
            l2RealityEth.getArbitrator(removalQuestionId),
            "Arbitrator of the removalQuestionId is l2ForkArbitrator"
        );

        uint256 forkFee = l2ForkArbitrator.getDisputeFee(removalQuestionId);
        vm.prank(user2);
        l2ForkArbitrator.requestArbitration{value: forkFee}(
            removalQuestionId,
            0
        );

        assertTrue(l2ForkArbitrator.isForkInProgress(), "In forking state");

        // L1 STUFF HAPPENS HERE
        // Assume somebody else called fork or the fee changed or something.
        // We should get a reply via the bridge.

        // NB Here we're sending the payment directly
        // In fact it seems like it would have to be claimed separately
        assertEq(address(l2ForkArbitrator).balance, 0);
        payable(address(l2Bridge)).transfer(1000000); // Fund it so it can fund the L2ForkArbitrator
        bytes memory fakeMessageData = abi.encode(removalQuestionId);
        l2Bridge.fakeClaimMessage(
            address(l1GlobalForkRequester),
            uint32(0),
            address(l2ForkArbitrator),
            fakeMessageData,
            forkFee
        );
        assertEq(address(l2ForkArbitrator).balance, forkFee);

        assertFalse(
            l2ForkArbitrator.isForkInProgress(),
            "Not in forking state"
        );

        l2ForkArbitrator.cancelArbitration(removalQuestionId);
        assertEq(forkFee, l2ForkArbitrator.refundsDue(user2));

        uint256 user2Bal = user2.balance;
        vm.prank(user2);
        l2ForkArbitrator.claimRefund();
        assertEq(address(l2ForkArbitrator).balance, 0);
        assertEq(user2.balance, user2Bal + forkFee);
    }

    function testAdjudicationFrameworkTemplateCreation() public {
        address[] memory initialArbs;
        vm.recordLogs();

        // Creates 2 templates, each with a log entry from reality.eth
        vm.prank(adjudictionDeployer);
        new AdjudicationFramework(
            address(l2RealityEth),
            123,
            address(l2ForkArbitrator),
            initialArbs
        );

        // NB The length and indexes of this may change if we add unrelated log entries to the AdjudicationFramework constructor
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2, "Should be 2 log entries");

        // We should always get the same contract address because we deploy only this with the same user so the address and nonce shouldn't change
        string
            memory addLog = '{"title": "Should we add arbitrator %s to the framework 0xfed866a553d106378b828a2e1effb8bed9c9dc28?", "type": "bool", "category": "adjudication", "lang": "en"}';
        string
            memory removeLog = '{"title": "Should we remove arbitrator %s and replace them by %s from the framework 0xfed866a553d106378b828a2e1effb8bed9c9dc28?", "type": "bool", "category": "adjudication", "lang": "en"}';

        assertEq(
            abi.decode(entries[0].data, (string)),
            string(removeLog),
            "removeLog missing"
        );
        assertEq(
            abi.decode(entries[1].data, (string)),
            string(addLog),
            "addLog missing"
        );
    }

    /*
    function testL1RequestGovernanceArbitration() public {
        bytes32 questionId = keccak256(abi.encodePacked("Question 1")); // TODO: This should be in some wrapper contract
        govArb.setDisputeFee(50);
        vm.mockCall(
            address(l1RealityEth),
            abi.encodeWithSelector(IRealityETH.isFinalized.selector),
            abi.encode(true)
        );
        assertTrue(govArb.requestArbitration{value: 50}(questionId, 0));
        assertEq(govArb.arbitration_bounties(questionId), 50);
    }
    */
}
