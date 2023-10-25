// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

// import {Arbitrator} from "./Arbitrator.sol";
import {L2ChainInfo} from "./L2ChainInfo.sol";
import {L1GlobalRouter} from "./L1GlobalRouter.sol";
import {IRealityETH} from "./interfaces/IRealityETH.sol";

import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";

/*
This contract is the arbitrator used by governance propositions for AdjudicationFramework contracts.
It charges a dispute fee of 5% of total supply [TODO], which it forwards to L1 when requesting a fork.
If there is already a dispute in progress (ie another fork has been requested but not triggered or we are in the 1 week period before a fork) the new one will be queued.
*/

// NB This doesn't implement IArbitrator because that requires slightly more functions than we need
// TODO: Would be good to make a stripped-down IArbitrator that only has the essential functions
contract L2ForkArbitrator {

    bool is_fork_in_progress;
    IRealityETH public realitio;

    enum RequestStatus {
        NONE,
        QUEUED,
        FORK_REQUESTED, // Fork is happening
        FORK_COMPLETED,  // Fork has happened
        REQUEST_FAILED   // TODO: Check if we need this or if we can just put it back to QUEUED
    }

    struct ArbitrationRequest {
        RequestStatus status; 
	address payable payer;
        uint256 paid;
	bytes32 result;
    } 

    event LogRequestArbitration(
        bytes32 indexed question_id,
        uint256 fee_paid,
        address requester,
        uint256 remaining
    );

    mapping(bytes32 => ArbitrationRequest) arbitration_requests;

    L2ChainInfo chainInfo;
    L1GlobalRouter router;

    uint256 public disputeFee; // The dispute fee should generally only go down
    uint256 public chainId;

    constructor(IRealityETH _realitio, L2ChainInfo _chainInfo, L1GlobalRouter _router, uint256 _initialDisputeFee) {
        realitio = _realitio;
        chainInfo = _chainInfo; 
        router = _router;
        disputeFee = _initialDisputeFee;
    }

    /// @notice Return the dispute fee for the specified question. 0 indicates that we won't arbitrate it.
    /// @dev Uses a general default, takes a question id param for other contracts that may want to set it per-question.
    function getDisputeFee(bytes32) public view returns (uint256) {
        return disputeFee;
    }



    /// @notice Request arbitration, freezing the question until we send submitAnswerByArbitrator
    /// @dev The bounty can be paid only in part, in which case the last person to pay will be considered the payer
    /// Will trigger an error if the notification fails, eg because the question has already been finalized
    /// @param question_id The question in question
    /// @param max_previous If specified, reverts if a bond higher than this was submitted after you sent your transaction.
    function requestArbitration(
        bytes32 question_id,
        uint256 max_previous
    ) external payable returns (bool) {
        uint256 arbitration_fee = getDisputeFee(question_id);
        require(
            arbitration_fee > 0,
            "The arbitrator must have set a non-zero fee for the question"
        );

        require(arbitration_requests[question_id].status == RequestStatus.NONE, "Already requested");

        arbitration_requests[question_id] = ArbitrationRequest(RequestStatus.QUEUED, payable(msg.sender), msg.value, bytes32(0));

	realitio.notifyOfArbitrationRequest(
	    question_id,
	    msg.sender,
	    max_previous
	);
	emit LogRequestArbitration(question_id, msg.value, msg.sender, 0);

        if (!is_fork_in_progress) {
            requestActivateFork(question_id); 
        }

	return true;
    }

    // Request a fork via the bridge
    // NB This may fail if someone else is already forking, and we'll have to retry after the fork.
    function requestActivateFork(
        bytes32 question_id
    ) public {
        RequestStatus status = arbitration_requests[question_id].status;
        require(status == RequestStatus.QUEUED || status == RequestStatus.REQUEST_FAILED, "question was not awaiting activation");
	arbitration_requests[question_id].status = RequestStatus.FORK_REQUESTED;
        // TODO: Send a message via the bridge, along with the payment
        IPolygonZkEVMBridge bridge = IPolygonZkEVMBridge(chainInfo.l2bridge());

        bytes memory qdata = bytes.concat(question_id);
        bridge.bridgeMessage(
            uint32(chainInfo.originNetwork()),
            address(router), // TODO: Use the fork requesting contract instead?
            false, // TODO: Work out if we need forceUpdateGlobalExitRoot
            qdata
        );
        is_fork_in_progress = true;
    }

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
    ) external {

        // TODO: Get this from L1 somehow
	//bytes32 answer = l1Directory.resultFor(question_id);
	bytes32 answer = bytes32("0x0");
        require(is_fork_in_progress, "No fork in progress to report");

        // Read from directory what the result was
        RequestStatus status = arbitration_requests[question_id].status;
        require(status == RequestStatus.FORK_REQUESTED, "question was not in fork requested state");

	arbitration_requests[question_id].status = RequestStatus.FORK_COMPLETED;
	is_fork_in_progress = false;

        realitio.assignWinnerAndSubmitAnswerByArbitrator(
            question_id,
            answer,
            arbitration_requests[question_id].payer,
            last_history_hash,
            last_answer_or_commitment_id,
            last_answerer
        );

    }

    function clearFailedForkAttempt(
        bytes32 question_id
    ) external {
        RequestStatus status = arbitration_requests[question_id].status;
        require(is_fork_in_progress, "No fork in progress to clear");
        require(status == RequestStatus.FORK_REQUESTED, "No attempt to clear for specified question");
        // Confirm from the bridge that the previous call failed
        // TODO: Do we need a contract on L2 that has this information?
        is_fork_in_progress = false;
    }

    /// @notice Cancel a previous arbitration request
    /// @dev This is intended for situations where the arbitration is happening non-atomically and the fee or something changes.
    /// @dev In our cases it should only happen if the fee is not up-to-date or a too-low fee was paid.
    /// @param question_id The question in question
    function cancelArbitration(bytes32 question_id) external {
        RequestStatus status = arbitration_requests[question_id].status;
        address payable payer = arbitration_requests[question_id].payer;
        require(status == RequestStatus.REQUEST_FAILED, "question was not in fork failed state");
        realitio.cancelArbitration(question_id);
        payer.transfer(arbitration_requests[question_id].paid);
    }

}
