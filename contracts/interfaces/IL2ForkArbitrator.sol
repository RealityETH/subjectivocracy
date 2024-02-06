// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

// Allow mixed-case variables for compatibility with reality.eth, eg it uses question_id not questionId
/* solhint-disable var-name-mixedcase */

import {IBridgeMessageReceiver} from "@RealityETH/zkevm-contracts/contracts/interfaces/IBridgeMessageReceiver.sol";

/*
This contract is the arbitrator used by governance propositions for AdjudicationFramework contracts.
It charges a dispute fee of 5% of total supply [TODO], which it forwards to L1 when requesting a fork.
If there is already a dispute in progress (ie another fork has been requested but not yet triggered or 
we are in the 1 week period before a fork) the new one will be queued.
*/

// NB This doesn't implement IArbitrator because that requires slightly more functions than we need
// TODO: Would be good to make a stripped-down IArbitrator that only has the essential functions
interface IL2ForkArbitrator is IBridgeMessageReceiver {
    // @dev Error thrown when the arbitration data is not set
    error ArbitrationDataNotSet();
    // @dev Error thrown when the arbitration fee is 0
    error ArbitrationFeeMustBePositive();
    // @dev Error thrown when the arbitration request has already been made
    error ArbitrationAlreadyRequested();
    // @dev Error thrown when the fork is already in progress over something else
    error ForkInProgress();
    // @dev Error thrown when the L2 bridge is not set
    error L2BridgeNotSet();
    // @dev Error thrown when the fork is not in progress
    error QuestionNotForked();
    // @dev Error thrown when status is not FORK_REQUESTED
    error StatusNotForkRequested();
    // @dev Error thrown when status is not FORK_REQUEST_FAILED
    error StatusNotForkRequestFailed();
    // @dev Error thrown when the fork is not in progress
    error WrongStatus();
    // @dev Error thrown when called with wrong network
    error WrongNetwork();
    // @dev Error thrown when called with wrong sender
    error WrongSender();
    // @dev Error thrown when called from the wrong bridge
    error WrongBridge();
    // @dev Error thrown when the fork is not in progress
    error ForkNotInProgress();
    // @dev Error thrown when contract is not awaiting activation
    error NotAwaitingActivation();
    // @dev Error thrown when the request is still in the waiting period
    error RequestStillInWaitingPeriod();

    /// @notice Return the dispute fee for the specified question. 0 indicates that we won't arbitrate it.
    /// @dev Uses a general default, takes a question id param for other contracts that may want to set it per-question.
    function getDisputeFee(bytes32) external view returns (uint256);

    /// @notice Request arbitration, freezing the question until we send submitAnswerByArbitrator
    /// @dev The bounty can be paid only in part, in which case the last person to pay will be considered the payer
    /// Will trigger an error if the notification fails, eg because the question has already been finalized
    /// @param questionId The question in question
    /// @param maxPrevious If specified, reverts if a bond higher than this was submitted after you sent your transaction.
    function requestArbitration(
        bytes32 questionId,
        uint256 maxPrevious
    ) external payable returns (bool);

    /// @notice Allows a requestor to top up their arbitration fee
    /// This function needs to be used, in case the arbitration fee was increased in the time period between
    /// the requestArbitration call and the arbitration request being processed.
    /// @param questionId The question in question
    function topUpArbitrationRequest(bytes32 questionId) external payable;

    /// @notice Request a fork via the bridge
    /// @dev Talks to the L1 ForkingManager asynchronously, and may fail.
    /// @param templateId The template id of the question during requestArbitration call
    /// @param openingTs The opening timestamp of the question during requestArbitration call
    /// @param question The question during requestArbitration call
    /// @param timeout The timeout of the question during requestArbitration call
    /// @param minBond The min bond of the question during requestArbitration call
    /// @param nonce The nonce of the question during requestArbitration call
    /// @param adjudicationFramework The address of the adjudication framework
    function requestActivateFork(
        uint256 templateId,
        uint32 openingTs,
        string calldata question,
        uint32 timeout,
        uint256 minBond,
        uint256 nonce,
        address adjudicationFramework
    ) external;

    // If the fork request fails, we will get a message back through the bridge telling us about it
    // We will set FORK_REQUEST_FAILED which will allow anyone to request cancellation
    function onMessageReceived(
        address _originAddress,
        uint32 _originNetwork,
        bytes memory _data
    ) external payable;

    /// @notice Submit the arbitrator's answer to a question, assigning the winner automatically.
    /// @param question_id The question in question
    /// @param last_history_hash The history hash before the final one
    /// @param last_answer_or_commitment_id The last answer given, or the commitment ID if it was a commitment.
    /// @param last_answerer The address that supplied the last answer
    function handleCompletedFork(
        bytes32 question_id,
        bytes32 last_history_hash,
        bytes32 last_answer_or_commitment_id,
        address last_answerer
    ) external;

    /// @notice Claim the refund for a question that was forked
    function claimRefund() external;
}
