// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

/* solhint-disable var-name-mixedcase */
/* solhint-disable quotes */
/* solhint-disable not-rely-on-time */

import {BalanceHolder} from "./../../lib/reality-eth/BalanceHolder.sol";

import {IRealityETH} from "./../../lib/reality-eth/interfaces/IRealityETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MinimalAdjudicationFramework} from "../MinimalAdjudicationFramework.sol";

/*
This contract sits between a Reality.eth instance and an Arbitrator.
It manages a allowlist of arbitrators, and makes sure questions can be sent to an arbitrator on the allowlist.
When called on to arbitrate, it pays someone to send out the arbitration job to an arbitrator on the allowlist.
Arbitrators can be disputed on L1.
To Reality.eth it looks like a normal arbitrator, implementing the Arbitrator interface.
To the normal Arbitrator contracts that does its arbitration jobs, it looks like Reality.eth.
*/

contract Requests is MinimalAdjudicationFramework, BalanceHolder {
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
    constructor(
        address _realityETH,
        uint256 _disputeFee,
        address _forkArbitrator,
        address[] memory _initialArbitrators
    )
        MinimalAdjudicationFramework(
            _realityETH,
            _forkArbitrator,
            _initialArbitrators
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
        require(
            arbitration_fee > 0,
            "Question must have fee" // "The arbitrator must have set a non-zero fee for the question"
        );
        require(msg.value >= arbitration_fee, "Insufficient fee");

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
        require(
            questionArbitrations[questionId].bounty > 0,
            "Not in queue" // Question must be in the arbitration queue
        );

        // The only time you can pick up a question that's already being arbitrated is if it's been removed from the allowlist
        if (questionArbitrations[questionId].arbitrator != address(0)) {
            require(
                !contains(questionArbitrations[questionId].arbitrator),
                "Question under arbitration" // Question already taken, and the arbitrator who took it is still active
            );

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
        require(old_arbitrator != address(0), "No arbitrator to remove");
        require(
            !contains(old_arbitrator),
            "Arbitrator not removed" // Arbitrator must no longer be on the allowlist
        );

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
        require(last_action_ts > 0, "Question not found");

        require(
            questionArbitrations[questionId].arbitrator == address(0),
            "Already under arbitration" // Question already accepted by an arbitrator
        );
        require(
            block.timestamp - last_action_ts > QUESTION_UNHANDLED_TIMEOUT,
            "Too soon to cancel" // You can only cancel questions that no arbitrator has accepted in a reasonable time
        );

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
        require(
            questionArbitrations[questionId].arbitrator == msg.sender,
            "Sender not the arbitrator" // An arbitrator can only submit their own arbitration result
        );
        require(
            questionArbitrations[questionId].bounty > 0,
            "Question not in queue"
        );

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

        require(contains(arbitrator), "Arbitrator must be allowlisted");
        require(
            countArbitratorFreezePropositions[arbitrator] == 0,
            "Arbitrator under dispute"
        );

        bytes32 data_hash = keccak256(
            abi.encodePacked(questionId, answer, answerer)
        );
        require(
            questionArbitrations[questionId].msg_hash == data_hash,
            "Resubmit previous parameters"
        );

        uint256 finalize_ts = questionArbitrations[questionId].finalize_ts;
        require(finalize_ts > 0, "Submission must have been queued");
        require(finalize_ts < block.timestamp, "Challenge deadline not passed");

        balanceOf[questionArbitrations[questionId].payer] =
            balanceOf[questionArbitrations[questionId].payer] +
            questionArbitrations[questionId].bounty;

        realityETH.submitAnswerByArbitrator(questionId, answer, answerer);
    }
}
