pragma solidity ^0.8.20;

/*
Tests for new features added to reality.eth while developing Subjectivocracy interaction.
Ultimately these will probably be moved to the reality.eth repo and included in a normal release
...unless it turns out that we need subjectivocracy-specific changes that we don't want in the normal version.
*/

/* solhint-disable not-rely-on-time */
/* solhint-disable reentrancy */
/* solhint-disable quotes */

import { Vm } from 'forge-std/Vm.sol';

import {Test} from "forge-std/Test.sol";
import {Arbitrator} from "../contracts/lib/reality-eth/Arbitrator.sol";
import {RealityETH_v3_0} from "../contracts/lib/reality-eth/RealityETH-3.0.sol";

contract RealityETHTest is Test {

    Arbitrator internal arb;
    RealityETH_v3_0 internal realityEth;
    bytes32 internal q1;
    bytes32 internal q2;

    address payable internal user1 = payable(address(0xbabe01));
    address payable internal user2 = payable(address(0xbabe02));

    bytes32 constant internal BYTES32_YES = bytes32(uint256(1));
    bytes32 constant internal BYTES32_NO = bytes32(uint256(0));

    bytes32[] internal historyHashes;
    address[] internal addrs;
    uint256[] internal bonds;
    bytes32[] internal answers;

    // Store the history for the number of entries set in numEntries in historyHashes etc
    function _logsToHistory(Vm.Log[] memory logs) internal {

        /*
        Some features need us to send the contract the answer history.
        This function will construct it from the logs in the order required.
        event LogNewAnswer(bytes32 answer, bytes32 indexed question_id, bytes32 history_hash, address indexed user, uint256 bond, uint256 ts, bool is_commitment)
        */

        bytes32 logNewAnswerSignature = keccak256("LogNewAnswer(bytes32,bytes32,bytes32,address,uint256,uint256,bool)");

        for(uint256 idx = logs.length; idx > 0; idx--) {

            uint256 i = idx - 1;

            // Skip any other log
            if (logs[i].topics[0] != logNewAnswerSignature) {
                continue;
            }

            (bytes32 logAnswer, bytes32 logHistoryHash, uint256 logBond,,) = abi.decode(logs[i].data, (bytes32,bytes32,uint256,uint256,bool));
            address logUser = address(uint160(uint256(logs[i].topics[2])));

            addrs.push(logUser);
            bonds.push(logBond);
            answers.push(logAnswer);
            historyHashes.push(logHistoryHash);

        }

        // historyHashes is in the reverse order (highest bond to lowest), go forwards now
        for(uint256 j = 0; j < historyHashes.length; j++) {
            // For the final element there is no next one, it's empty
            if (j < historyHashes.length-1) {
                historyHashes[j] = historyHashes[j+1];
            } else {
                historyHashes[j] = bytes32(0);
            }
        }

    }


    function _trimLogs() internal {

        historyHashes.pop();
        addrs.pop();
        bonds.pop();
        answers.pop();
    }

    function setUp() public {

        realityEth = new RealityETH_v3_0();

        arb = new Arbitrator();
        arb.setRealitio(address(realityEth));
        arb.setDisputeFee(50);

        user1.transfer(1000000);
        user2.transfer(1000000);

        q1 = realityEth.askQuestion(0, "Question 1", address(arb), uint32(6000), 0, 0);
        q2 = realityEth.askQuestion(0, "Question 2", address(arb), uint32(6000), 0, 0);

        vm.recordLogs();

        vm.prank(user1);
        realityEth.submitAnswer{value: 5}(q1, BYTES32_YES, 0);

        vm.prank(user2);
        realityEth.submitAnswer{value: 25}(q1, BYTES32_NO, 0);

        vm.prank(user1);
        realityEth.submitAnswer{value: 500}(q1, BYTES32_YES, 0);

        // Put an unrevealed commit at 1000
        uint256 nonce1 = uint256(555554321);
        bytes32 answerHash1 = keccak256(abi.encodePacked(BYTES32_NO, nonce1));
        uint256 bond1 = 1000;
        vm.prank(user1);
        realityEth.submitAnswerCommitment{value: bond1}(q1, answerHash1, 0, user1);

        vm.prank(user2);
        realityEth.submitAnswer{value: 2500}(q1, BYTES32_NO, 0);

        // We'll do this one as a commit-reveal
        uint256 nonce2 = uint256(1232);
        bytes32 answerHash2 = keccak256(abi.encodePacked(BYTES32_NO, nonce2));
        uint256 bond2 = 5000;
        vm.prank(user2);
        realityEth.submitAnswerCommitment{value: bond2}(q1, answerHash2, 0, user2);
        realityEth.submitAnswerReveal(q1, BYTES32_NO, nonce2, bond2);

        // Do a commit-reveal for yes
        uint256 nonce3 = uint256(9876);
        bytes32 answerHash3 = keccak256(abi.encodePacked(BYTES32_YES, nonce3));
        uint256 bond3 = 10000;
        vm.prank(user1);
        realityEth.submitAnswerCommitment{value: bond3}(q1, answerHash3, 0, user1);
        realityEth.submitAnswerReveal(q1, BYTES32_YES, nonce3, bond3);

        vm.prank(user1);
        realityEth.submitAnswer{value: 20000}(q1, BYTES32_YES, 0);

        vm.prank(user2);
        realityEth.submitAnswer{value: 40000}(q1, BYTES32_NO, 0);

        _logsToHistory(vm.getRecordedLogs());

    }

    function _checkSuppliedHistory(bytes32 expectedAnswer, uint256 expectedBond) internal {

        (bytes32 finalAnswer, uint256 finalBond) = realityEth.getEarliestAnswerFromSuppliedHistoryOrRevert(q1, historyHashes, addrs, bonds, answers);
        assertEq(finalAnswer, expectedAnswer);
        assertEq(finalBond, expectedBond);

    }

    function _checkSuppliedHistoryUnrevealedCommit() internal {

        vm.expectRevert("Earliest answer is an unrevealed commitment");
        realityEth.getEarliestAnswerFromSuppliedHistoryOrRevert(q1, historyHashes, addrs, bonds, answers);

    }

    function testGetEarliestAnswerFromSuppliedHistoryOrRevert() public {

        _checkSuppliedHistory(BYTES32_YES, 5);
        _trimLogs();
        _checkSuppliedHistory(BYTES32_NO, 25);
        _trimLogs();
        _checkSuppliedHistory(BYTES32_YES, 500);
        _trimLogs();
        _checkSuppliedHistoryUnrevealedCommit();
        _trimLogs();
        _checkSuppliedHistory(BYTES32_NO, 2500);
        _trimLogs();
        _checkSuppliedHistory(BYTES32_NO, 5000);
        _trimLogs();
        _checkSuppliedHistory(BYTES32_YES, 10000);
        _trimLogs();
        _checkSuppliedHistory(BYTES32_YES, 20000);
        _trimLogs();
        _checkSuppliedHistory(BYTES32_NO, 40000);

    }

    function testGetEarliestAnswerFromSuppliedHistoryOrRevertWrongHashReverts() public {

        // Make one of the history hashes wrong
        historyHashes[2] = bytes32(0);
        vm.expectRevert("History input provided did not match the expected hash");
        realityEth.getEarliestAnswerFromSuppliedHistoryOrRevert(q1, historyHashes, addrs, bonds, answers);

    }

}
