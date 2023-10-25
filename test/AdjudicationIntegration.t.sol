pragma solidity ^0.8.20;
import {Test} from "forge-std/Test.sol";
import {Arbitrator} from "../contracts/Arbitrator.sol";

// TODO: Replace this with whatever zkEVM or whatever platform we're on uses
import {IAMB} from "../contracts/interfaces/IAMB.sol";

import {IRealityETH} from "../contracts/interfaces/IRealityETH.sol";
import {IERC20} from "../contracts/interfaces/IERC20.sol";
import {ForkableRealityETH_ERC20} from "../contracts/ForkableRealityETH_ERC20.sol";
import {RealityETH_v3_0} from "../contracts/RealityETH-3.0.sol";
import {AdjudicationFramework} from "../contracts/AdjudicationFramework.sol";

import {L2ForkArbitrator} from "../contracts/L2ForkArbitrator.sol";
import {L1GlobalRouter} from "../contracts/L1GlobalRouter.sol";
import {L2ChainInfo} from "../contracts/L2ChainInfo.sol";

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

    // TODO: In an earlier version these were special hard-coded values at the top end of the ID range.
    // Consider whether we should do that, or call createTemplate() when we set up the realityeth contract.
    uint256 constant TEMPLATE_ID_ADD_ARBITRATOR = 1;
    uint256 constant TEMPLATE_ID_REMOVE_ARBITRATOR = 2;
    uint256 constant TEMPLATE_ID_SWITCH_FORKMANAGER = 3;

    uint32 constant REALITY_ETH_TIMEOUT = 86400;

    // dummy addresses for things we message on l1
    address l2Bridge = address(0xbabe11);
    address l1GlobalRouter = address(0xbabe12);
    address l1ForkingManager = address(0xbabe13);
    address l1Token = address(0xbabe14);

    function setUp() public {

        // For now the values of the l1 contracts are all made up
        // Ultimately our tests should include a deployment on l1

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

        uint256 forkingFee = 5000; // TODO
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

    function testContestedArbitration() public {

        bytes32 qid = _setupContestableQuestion();

        _setupArbitratedQuestion(qid);

        // TODO: Separate this part out to reuse in different tests for uncontested freeze and fork?

        // permitted arbitrator grabs the question off the queue and locks it so nobody else can get it
        assertTrue(l2Arbitrator1.requestArbitration{value: 500000}(qid, 0));
        l2Arbitrator1.submitAnswerByArbitrator(qid, bytes32(uint256(1)), user1);

        vm.expectRevert("Challenge deadline must have passed");
        adjudicationFramework1.completeArbitration(qid, bytes32(uint256(1)), user1);

        // now before we can complete this somebody challenges it
        bytes32 removal_question_id = adjudicationFramework1.beginRemoveArbitratorFromAllowList(address(l2Arbitrator1));

        vm.expectRevert("Bond too low to freeze");
        adjudicationFramework1.freezeArbitrator(removal_question_id);

        l2realityEth.submitAnswer{value: 20000}(removal_question_id, bytes32(uint256(1)), 0);
        adjudicationFramework1.freezeArbitrator(removal_question_id);

        skip(86401);
        vm.expectRevert("Arbitrator must not be under dispute");
        adjudicationFramework1.completeArbitration(qid, bytes32(uint256(1)), user1);

        /* Next step
            a) Make a governance proposition on L1, escalating to a fork
            b) Make a direct fork request on L1 via the bridge
            c) Make a fork request on L2, get the response via the bridge
        */

    }

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

    function _toString(bytes memory data)
    internal pure returns(string memory) {
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = '0';
        str[1] = 'x';
        for (uint i = 0; i < data.length; i++) {
                str[2+i*2] = alphabet[uint(uint8(data[i] >> 4))];
                str[3+i*2] = alphabet[uint(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }

}
