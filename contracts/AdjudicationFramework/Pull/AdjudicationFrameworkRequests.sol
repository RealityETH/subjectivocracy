// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

/* solhint-disable var-name-mixedcase */
/* solhint-disable quotes */
/* solhint-disable not-rely-on-time */

import {BalanceHolder} from "./../../lib/reality-eth/BalanceHolder.sol";
import {MinimalAdjudicationFramework} from "../MinimalAdjudicationFramework.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/*
This contract sits between a Reality.eth instance and an Arbitrator.
It manages a allowlist of arbitrators, and makes sure questions can be sent to an arbitrator on the allowlist.
When called on to arbitrate, it pays someone to send out the arbitration job to an arbitrator on the allowlist.
Arbitrators can be disputed on L1.
To Reality.eth it looks like a normal arbitrator, implementing the Arbitrator interface.
To the normal Arbitrator contracts that does its arbitration jobs, it looks like Reality.eth.
*/

contract AdjudicationFrameworkRequests is
    MinimalAdjudicationFramework,
    BalanceHolder
{
    using EnumerableSet for EnumerableSet.AddressSet;
    /// @dev Error thrown when challenge deadline has not passed
    error ChallengeDeadlineNotPassed();
    /// @dev Error thrown when submission must have been queued
    error SubmissionMustHaveBeenQueued();
    /// @dev Error thrown when resubmission of previous parameters
    error ResubmissionOfPReviousParameters();
    /// @dev Error thrown when arbitrator must be allowlisted
    error ArbitratorMustBeAllowlisted();
    /// @dev Error thrown when arbitrator under dispute
    error ArbitratorUnderDispute();
    /// @dev Error thrown when arbitrator address is zero
    error ArbitratorAddressZero();
    /// @dev Error thrown when arbitrator not removed
    error ArbitratorNotRemoved();
    /// @dev Error thrown when arbitrator not sender
    error ArbitratorNotSender();
    /// @dev Error thrown when question already under arbitration
    error QuestionAlreadyUnderArbitration();
    /// @dev Error thrown when question under arbitration
    error QuestionUnderArbitration();
    /// @dev Error thrown when question not in queue
    error QuestionNotFound();
    /// @dev Error thrown when question must have a fee
    error QuestionMustHaveAFee();
    /// @dev Error thrown when insufficient fee
    error InsufficientFee();
    /// @dev Error thrown when question not in queue
    error QuestionNotInQueue();
    /// @dev Error thrown when too soon to cancel
    error TooSoonToCancel();

    event LogRequestArbitration(
        bytes32 indexed questionId,
        uint256 feePaid,
        address requester,
        uint256 remaining
    );

    event LogNotifyOfArbitrationRequest(
        bytes32 indexed questionId,
        address indexed user
    );

    uint256 public dispute_fee;

    struct ArbitrationRequest {
        address arbitrator;
        address payer;
        uint256 bounty;
        bytes32 msg_hash;
        uint256 finalize_ts;
        uint256 last_action_ts;
    }

    mapping(bytes32 => ArbitrationRequest) public questionArbitrations;

    /// @param _realityETH The reality.eth instance we adjudicate for
    /// @param _disputeFee The dispute fee we charge reality.eth users
    /// @param _forkArbitrator The arbitrator contract that escalates to an L1 fork, used for our governance
    /// @param _initialArbitrators Arbitrator contracts we initially support
        /// @param _arbitrationDelayForCollectingEvidence The delay before arbitration can be requested

    constructor(
        address _realityETH,
        uint256 _disputeFee,
        address _forkArbitrator,
        address[] memory _initialArbitrators,
        bool _allowReplacementModification,
        uint256 _arbitrationDelayForCollectingEvidence
    )
        MinimalAdjudicationFramework(
            _realityETH,
            _forkArbitrator,
            _initialArbitrators,
            _allowReplacementModification,
            _arbitrationDelayForCollectingEvidence
        )
    {
        dispute_fee = _disputeFee;
    }

    /// @notice Return the dispute fee for the specified question. 0 indicates that we won't arbitrate it.
    /// @dev Uses a general default, but can be over-ridden on a question-by-question basis.
    function getDisputeFee(bytes32) public view returns (uint256) {
        // TODO: Should we have a governance process to change this?
        return dispute_fee;
    }

    /// @notice Request arbitration, freezing the question until we send submitAnswerByArbitrator
    /// @dev Will trigger an error if the notification fails, eg because the question has already been finalized
    /// @param questionId The question in question
    /// @param max_previous If specified, reverts if a bond higher than this was submitted after you sent your transaction.
    function requestArbitration(
        bytes32 questionId,
        uint256 max_previous
    ) external payable returns (bool) {
        uint256 arbitration_fee = getDisputeFee(questionId);
        if (arbitration_fee == 0) {
            revert QuestionMustHaveAFee();
        }
        if (msg.value < arbitration_fee) {
            revert InsufficientFee();
        }

        realityETH.notifyOfArbitrationRequest(
            questionId,
            msg.sender,
            max_previous
        );
        emit LogRequestArbitration(questionId, msg.value, msg.sender, 0);

        // Queue the question for arbitration by a allowlisted arbitrator
        // Anybody can take the question off the queue and submit it to a allowlisted arbitrator
        // They will have to pay the arbitration fee upfront
        // They can claim the bounty when they get an answer
        // If the arbitrator is removed in the meantime, they'll lose the money they spent on arbitration
        questionArbitrations[questionId].payer = msg.sender;
        questionArbitrations[questionId].bounty = msg.value;
        questionArbitrations[questionId].last_action_ts = block.timestamp;

        return true;
    }

    // This function is normally in Reality.eth.
    // We put it here so that we can be treated like Reality.eth from the pov of the arbitrator contract.

    /// @notice Notify the contract that the arbitrator has been paid for a question, freezing it pending their decision.
    /// @dev The arbitrator contract is trusted to only call this if they've been paid, and tell us who paid them.
    /// @param questionId The ID of the question
    /// @param requester The account that requested arbitration
    function notifyOfArbitrationRequest(
        bytes32 questionId,
        address requester,
        uint256
    ) external onlyArbitrator {
        if (questionArbitrations[questionId].bounty == 0) {
            revert QuestionNotInQueue();
        }

        // The only time you can pick up a question that's already being arbitrated is if it's been removed from the allowlist
        if (questionArbitrations[questionId].arbitrator != address(0)) {
            if (
                _arbitrators.contains(
                    questionArbitrations[questionId].arbitrator
                )
            ) {
                revert QuestionUnderArbitration();
            }

            // Clear any in-progress data from the arbitrator that has now been removed
            questionArbitrations[questionId].msg_hash = 0x0;
            questionArbitrations[questionId].finalize_ts = 0;
        }

        questionArbitrations[questionId].payer = requester;
        questionArbitrations[questionId].arbitrator = msg.sender;

        emit LogNotifyOfArbitrationRequest(questionId, requester);
    }

    /// @notice Clear the arbitrator setting of an arbitrator that has been delisted
    /// @param questionId The question in question
    /// @dev Starts the clock ticking to allow us to cancelUnhandledArbitrationRequest
    /// @dev Not otherwise needed, if another arbitrator shows up they can just take the job from the delisted arbitrator
    function clearRequestFromRemovedArbitrator(bytes32 questionId) external {
        address old_arbitrator = questionArbitrations[questionId].arbitrator;
        if (old_arbitrator == address(0)) {
            revert ArbitratorAddressZero();
        }
        if (_arbitrators.contains(old_arbitrator)) {
            revert ArbitratorNotRemoved();
        }

        questionArbitrations[questionId].arbitrator = address(0);
        questionArbitrations[questionId].msg_hash = 0x0;
        questionArbitrations[questionId].finalize_ts = 0;

        questionArbitrations[questionId].last_action_ts = block.timestamp;
    }

    /// @notice Cancel the request for arbitration
    /// @param questionId The question in question
    /// @dev This is only done if nobody takes the request off the queue, probably because the fee is too low
    function cancelUnhandledArbitrationRequest(bytes32 questionId) external {
        uint256 last_action_ts = questionArbitrations[questionId]
            .last_action_ts;
        if (last_action_ts == 0) {
            revert QuestionNotFound();
        }
        if (questionArbitrations[questionId].arbitrator != address(0)) {
            revert QuestionAlreadyUnderArbitration(); // Question already accepted by an arbitrator
        }
        if (block.timestamp - last_action_ts <= QUESTION_UNHANDLED_TIMEOUT) {
            revert TooSoonToCancel(); // You can only cancel questions that no arbitrator has accepted in a reasonable time
        }

        // Refund the arbitration bounty
        balanceOf[questionArbitrations[questionId].payer] =
            balanceOf[questionArbitrations[questionId].payer] +
            questionArbitrations[questionId].bounty;
        delete questionArbitrations[questionId];
        realityETH.cancelArbitration(questionId);
    }

    // The arbitrator submits the answer to us, instead of to realityETH
    // Instead of sending it to Reality.eth, we instead hold onto it for a challenge period in case someone disputes the arbitrator.
    // TODO: We may need assignWinnerAndSubmitAnswerByArbitrator here instead

    /// @notice Submit the arbitrator's answer to a question.
    /// @param questionId The question in question
    /// @param answer The answer
    /// @param answerer The answerer. If arbitration changed the answer, it should be the payer. If not, the old answerer.
    /// @dev solc will complain about unsued params but they're used, just via msg.data
    function submitAnswerByArbitrator(
        bytes32 questionId,
        bytes32 answer,
        address answerer
    ) public {
        if (questionArbitrations[questionId].arbitrator != msg.sender) {
            revert ArbitratorNotSender(); // An arbitrator can only submit their own arbitration result
        }
        if (questionArbitrations[questionId].bounty == 0) {
            revert QuestionNotInQueue(); // Question not in queue
        }

        bytes32 data_hash = keccak256(
            abi.encodePacked(questionId, answer, answerer)
        );
        uint256 finalize_ts = block.timestamp + ARB_DISPUTE_TIMEOUT;

        questionArbitrations[questionId].msg_hash = data_hash;
        questionArbitrations[questionId].finalize_ts = finalize_ts;
    }

    /// @notice Resubmit the arbitrator's answer to a question once the challenge period for it has passed
    /// @param questionId The question in question
    /// @param answer The answer
    /// @param answerer The answerer. If arbitration changed the answer, it should be the payer. If not, the old answerer.
    function completeArbitration(
        bytes32 questionId,
        bytes32 answer,
        address answerer
    ) external {
        address arbitrator = questionArbitrations[questionId].arbitrator;

        if (!_arbitrators.contains(arbitrator)) {
            revert ArbitratorMustBeAllowlisted();
        }
        if (countArbitratorFreezePropositions[arbitrator] != 0) {
            revert ArbitratorUnderDispute();
        }

        bytes32 data_hash = keccak256(
            abi.encodePacked(questionId, answer, answerer)
        );
        if (questionArbitrations[questionId].msg_hash != data_hash) {
            revert ResubmissionOfPReviousParameters();
        }

        uint256 finalize_ts = questionArbitrations[questionId].finalize_ts;
        if (finalize_ts == 0) {
            revert SubmissionMustHaveBeenQueued();
        }
        if (finalize_ts > block.timestamp) {
            revert ChallengeDeadlineNotPassed();
        }

        balanceOf[questionArbitrations[questionId].payer] =
            balanceOf[questionArbitrations[questionId].payer] +
            questionArbitrations[questionId].bounty;

        realityETH.submitAnswerByArbitrator(questionId, answer, answerer);
    }
}
