// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

// Allow mixed-case variables for compatibility with reality.eth, eg it uses question_id not questionId
/* solhint-disable var-name-mixedcase */

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

    bool public isForkInProgress;
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

    mapping(bytes32 => ArbitrationRequest) public arbitrationRequests;

    L2ChainInfo public chainInfo;
    L1GlobalRouter public router;

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
            "fee must be positive"
        );

        require(arbitrationRequests[question_id].status == RequestStatus.NONE, "Already requested");

        arbitrationRequests[question_id] = ArbitrationRequest(RequestStatus.QUEUED, payable(msg.sender), msg.value, bytes32(0));

	realitio.notifyOfArbitrationRequest(
	    question_id,
	    msg.sender,
	    max_previous
	);
	emit LogRequestArbitration(question_id, msg.value, msg.sender, 0);

        if (!isForkInProgress) {
           requestActivateFork(question_id); 
        }

	return true;
    }

    // Request a fork via the bridge
    // NB This may fail if someone else is already forking, and we'll have to retry after the fork.
    function requestActivateFork(
        bytes32 question_id
    ) public {
        RequestStatus status = arbitrationRequests[question_id].status;
        require(status == RequestStatus.QUEUED || status == RequestStatus.REQUEST_FAILED, "not awaiting activation");
	arbitrationRequests[question_id].status = RequestStatus.FORK_REQUESTED;
        // TODO: Send a message via the bridge, along with the payment

        address l2bridge = chainInfo.l2bridge();
        require(l2bridge != address(0), "l2bridge not set");

        IPolygonZkEVMBridge bridge = IPolygonZkEVMBridge(l2bridge);

        bytes memory qdata = bytes.concat(question_id);
        bridge.bridgeMessage(
            uint32(chainInfo.originNetwork()),
            address(router), // TODO: Use the fork requesting contract instead?
            false, // TODO: Work out if we need forceUpdateGlobalExitRoot
            qdata
        );
        isForkInProgress = true;
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

        // Read from directory what the result was
        RequestStatus status = arbitrationRequests[question_id].status;
        require(status == RequestStatus.FORK_REQUESTED, "not in fork-requested state");

        require(chainInfo.questionToChainID(question_id) > 0, "Dispute not found in ChainInfo");

        // We get the fork result from the L2ChainInfo contract
        // One answer is assigned to each fork
        // TODO: Is this best, or is it better to bridge it directly?
        bytes32 answer = chainInfo.forkQuestionResults(question_id);

	arbitrationRequests[question_id].status = RequestStatus.FORK_COMPLETED;
	isForkInProgress = false;

        realitio.assignWinnerAndSubmitAnswerByArbitrator(
            question_id,
            answer,
            arbitrationRequests[question_id].payer,
            last_history_hash,
            last_answer_or_commitment_id,
            last_answerer
        );

    }

    function clearFailedForkAttempt(
        bytes32 question_id
    ) external {
        RequestStatus status = arbitrationRequests[question_id].status;
        require(isForkInProgress, "No fork in progress to clear");
        require(status == RequestStatus.FORK_REQUESTED, "Nothing to clear");
        // Confirm from the bridge that the previous call failed
        // TODO: Do we need a contract on L2 that has this information?
        isForkInProgress = false;
    }

    /// @notice Cancel a previous arbitration request
    /// @dev This is intended for situations where the arbitration is happening non-atomically and the fee or something changes.
    /// @dev In our cases it should only happen if the fee is not up-to-date or a too-low fee was paid.
    /// @param question_id The question in question
    function cancelArbitration(bytes32 question_id) external {
        RequestStatus status = arbitrationRequests[question_id].status;
        address payable payer = arbitrationRequests[question_id].payer;
        require(status == RequestStatus.REQUEST_FAILED, "Not in fork-failed state");
        realitio.cancelArbitration(question_id);
        payer.transfer(arbitrationRequests[question_id].paid);
    }

}
