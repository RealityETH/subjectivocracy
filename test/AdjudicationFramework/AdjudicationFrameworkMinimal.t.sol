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
import {AdjudicationFrameworkRequests} from "../../contracts/AdjudicationFramework/Pull/AdjudicationFrameworkRequests.sol";

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

    AdjudicationFrameworkRequests internal adjudicationFramework1;
    AdjudicationFrameworkRequests internal adjudicationFramework2;

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
        adjudicationFramework1 = new AdjudicationFrameworkRequests(
            address(l2RealityEth),
            123,
            address(l2ForkArbitrator),
            initialArbitrators,
            true
        );

        l2Arbitrator1 = new Arbitrator();
        // NB The adjudication framework looks to individual arbitrators like a reality.eth question, so they can use it without being changed.
        l2Arbitrator1.setRealitio(address(adjudicationFramework1));
        l2Arbitrator1.setDisputeFee(50);

        // Set up another idential arbitrator but don't add them to the framework yet.
        l2Arbitrator2 = new Arbitrator();
        l2Arbitrator2.setRealitio(address(adjudicationFramework1));
        l2Arbitrator2.setDisputeFee(50);

        // Create a question - from requestModificationOfArbitrators
        // For the setup we'll do this as an uncontested addition.
        // Contested cases should also be tested.
        addArbitratorQID1 = adjudicationFramework1
            .requestModificationOfArbitrators(
                address(0),
                address(l2Arbitrator1)
            );
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
        adjudicationFramework1.executeModificationArbitratorFromAllowList(
            addArbitratorQID1
        );

        skip(86401);
        adjudicationFramework1.executeModificationArbitratorFromAllowList(
            addArbitratorQID1
        );

        assertTrue(adjudicationFramework1.isArbitrator(address(l2Arbitrator1)));
    }

    function _simulateRealityEthAnswer(
        bytes32 questionId,
        bool answer
    ) internal {
        uint256 answerInt = answer ? 1 : 0;
        l2RealityEth.submitAnswer{value: 40000}(
            questionId,
            bytes32(answerInt),
            0
        );
        skip(86401);
    }

    function testInitialArbitrators() public {
        // Initial arbitrators from the contructor should be added
        assertTrue(adjudicationFramework1.isArbitrator(initialArbitrator1));
        assertTrue(adjudicationFramework1.isArbitrator(initialArbitrator2));
        // This arbitrator may be added in other tests by creating a proposition
        assertFalse(
            adjudicationFramework1.isArbitrator(address(l2Arbitrator2))
        );
    }

    function testAdjudicationFrameworkTemplateCreation() public {
        address[] memory initialArbs;
        vm.recordLogs();

        // Creates 2 templates, each with a log entry from reality.eth
        vm.prank(adjudictionDeployer);
        new AdjudicationFrameworkRequests(
            address(l2RealityEth),
            123,
            address(l2ForkArbitrator),
            initialArbs,
            true
        );

        // NB The length and indexes of this may change if we add unrelated log entries to the AdjudicationFramework constructor
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 3, "Should be 2 log entries");

        // We should always get the same contract address because we deploy only this with the same user so the address and nonce shouldn't change
        string
            memory addLog = '{"title": "Should we add arbitrator %s to the framework 0xfed866a553d106378b828a2e1effb8bed9c9dc28?", "type": "bool", "category": "adjudication", "lang": "en"}';
        string
            memory removeLog = '{"title": "Should we remove arbitrator %s from the framework 0xfed866a553d106378b828a2e1effb8bed9c9dc28?", "type": "bool", "category": "adjudication", "lang": "en"}';
        string
            memory replaceLog = '{"title": "Should we replace the arbitrator %s by the new arbitrator %s to the framework 0xfed866a553d106378b828a2e1effb8bed9c9dc28?", "type": "bool", "category": "adjudication", "lang": "en"}';

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
        assertEq(
            abi.decode(entries[2].data, (string)),
            string(replaceLog),
            "replaceLog missing"
        );
    }

    function testrequestModificationOfArbitrators() public {
        // Scenario 1: Add 1 arbitrator

        bytes32 questionIdAddMultiple = adjudicationFramework1
            .requestModificationOfArbitrators(address(0), address(0x1000));
        assertNotEq(
            questionIdAddMultiple,
            bytes32(0),
            "Failed to add multiple arbitrators"
        );

        // Scenario 2: Remove an arbitrator

        bytes32 questionIdRemove = adjudicationFramework1
            .requestModificationOfArbitrators(initialArbitrator1, address(0));
        assertNotEq(
            questionIdRemove,
            bytes32(0),
            "Failed to remove arbitrator"
        );

        // Scenario 3: Invalid case - twice the same arbitrators
        vm.expectRevert("question must not exist");
        adjudicationFramework1.requestModificationOfArbitrators(
            initialArbitrator1,
            address(0)
        );

        // Scenario 4: Invalid case - No arbitrators to modify
        vm.expectRevert("No arbitrators to modify");
        adjudicationFramework1.requestModificationOfArbitrators(
            address(0),
            address(0)
        );
    }
    function testExecuteModificationArbitratorFromAllowList() public {
        // Add an arbitrator

        bytes32 questionIdAdd = adjudicationFramework1
            .requestModificationOfArbitrators(address(0), address(0x2000));
        _simulateRealityEthAnswer(questionIdAdd, true); // Assuming this is a helper function to simulate the answer from RealityETH

        adjudicationFramework1.executeModificationArbitratorFromAllowList(
            questionIdAdd
        );
        assertTrue(
            adjudicationFramework1.isArbitrator(address(0x2000)),
            "Arbitrator was not added"
        );

        // Remove an arbitrator
        bytes32 questionIdRemove = adjudicationFramework1
            .requestModificationOfArbitrators(address(0x2000), address(0));
        _simulateRealityEthAnswer(questionIdRemove, true);

        adjudicationFramework1.executeModificationArbitratorFromAllowList(
            questionIdRemove
        );
        assertFalse(
            adjudicationFramework1.isArbitrator(address(0x2000)),
            "Arbitrator was not removed"
        );
    }

    function testFreezeArbitratorAndClearFailedProposition() public {
        // Freeze an arbitrator

        bytes32 questionId = adjudicationFramework1
            .requestModificationOfArbitrators(initialArbitrator1, address(0));

        // set temp answer to allow freezeArbitrator() to be called
        uint256 tempAnswerInt = 1;
        l2RealityEth.submitAnswer{value: 20000}(
            questionId,
            bytes32(tempAnswerInt),
            0
        );
        vm.expectRevert("question must be finalized");
        adjudicationFramework1.clearFailedProposition(questionId);

        // Assume freezeArbitrator() will be called here with appropriate parameters
        adjudicationFramework1.freezeArbitrator(
            questionId,
            new bytes32[](0),
            new address[](0),
            new uint256[](0),
            new bytes32[](0)
        );

        _simulateRealityEthAnswer(questionId, false);

        // Clear failed proposition
        adjudicationFramework1.clearFailedProposition(questionId);
        assertFalse(
            adjudicationFramework1.isArbitratorPropositionFrozen(questionId),
            "Failed to clear failed proposition"
        );
    }

    function testclearFailedPropositionCantBeCalledIfPropositionWentThrough()
        public
    {
        // Freeze an arbitrator
        bytes32 questionId = adjudicationFramework1
            .requestModificationOfArbitrators(initialArbitrator1, address(0));

        _simulateRealityEthAnswer(questionId, true);

        // Clear failed proposition
        vm.expectRevert("Result was not 0");
        adjudicationFramework1.clearFailedProposition(questionId);
    }
}
