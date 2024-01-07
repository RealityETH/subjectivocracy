// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

// Allow mixed-case variables for compatibility with reality.eth, eg it uses question_id not questionId
/* solhint-disable var-name-mixedcase */

import {L2ChainInfo} from "./L2ChainInfo.sol";
import {L1GlobalForkRequester} from "./L1GlobalForkRequester.sol";
import {IRealityETH} from "./lib/reality-eth/interfaces/IRealityETH.sol";
import {CalculateMoneyBoxAddress} from "./lib/CalculateMoneyBoxAddress.sol";

import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {IBridgeMessageReceiver} from "@RealityETH/zkevm-contracts/contracts/interfaces/IBridgeMessageReceiver.sol";

/*
This contract is the arbitrator used by governance propositions for AdjudicationFramework contracts.
It charges a dispute fee of 5% of total supply [TODO], which it forwards to L1 when requesting a fork.
If there is already a dispute in progress (ie another fork has been requested but not yet triggered or 
we are in the 1 week period before a fork) the new one will be queued.
*/

// NB This doesn't implement IArbitrator because that requires slightly more functions than we need
// TODO: Would be good to make a stripped-down IArbitrator that only has the essential functions
contract L2ForkArbitrator is IBridgeMessageReceiver {
    bool public isForkInProgress;
    IRealityETH public realitio;

    enum RequestStatus {
        NONE,
        QUEUED, // We got our payment and put the reality.eth process on hold, but haven't requested initialization yet
        FORK_REQUESTED, // Fork request set to L1, result unknown so far
        FORK_REQUEST_FAILED // Fork request failed, eg another process was forking
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
    mapping(address => uint256) public refundsDue;

    L2ChainInfo public chainInfo;
    L1GlobalForkRequester public l1GlobalForkRequester;

    uint256 public disputeFee; // Normally dispute fee should generally only go down in a fork

    constructor(
        IRealityETH _realitio,
        L2ChainInfo _chainInfo,
        L1GlobalForkRequester _l1GlobalForkRequester,
        uint256 _initialDisputeFee
    ) {
        realitio = _realitio;
        chainInfo = _chainInfo;
        l1GlobalForkRequester = _l1GlobalForkRequester;
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
    /// @param questionId The question in question
    /// @param maxPrevious If specified, reverts if a bond higher than this was submitted after you sent your transaction.
    function requestArbitration(
        bytes32 questionId,
        uint256 maxPrevious
    ) external payable returns (bool) {
        uint256 arbitration_fee = getDisputeFee(questionId);
        require(arbitration_fee > 0, "fee must be positive");

        require(
            arbitrationRequests[questionId].status == RequestStatus.NONE,
            "Already requested"
        );

        arbitrationRequests[questionId] = ArbitrationRequest(
            RequestStatus.QUEUED,
            payable(msg.sender),
            msg.value,
            bytes32(0)
        );

        realitio.notifyOfArbitrationRequest(
            questionId,
            msg.sender,
            maxPrevious
        );
        emit LogRequestArbitration(questionId, msg.value, msg.sender, 0);

        if (!isForkInProgress) {
            requestActivateFork(questionId);
        }
        return true;
    }

    /// @notice Request a fork via the bridge
    /// @dev Talks to the L1 ForkingManager asynchronously, and may fail.
    /// @param question_id The question in question
    function requestActivateFork(bytes32 question_id) public {
        require(!isForkInProgress, "Already forking"); // Forking over something else

        RequestStatus status = arbitrationRequests[question_id].status;
        require(
            status == RequestStatus.QUEUED ||
                status == RequestStatus.FORK_REQUEST_FAILED,
            "not awaiting activation"
        );
        arbitrationRequests[question_id].status = RequestStatus.FORK_REQUESTED;

        uint256 forkFee = chainInfo.getForkFee();
        uint256 paid = arbitrationRequests[question_id].paid;
        require(paid >= forkFee, "fee paid too low");

        address l2Bridge = chainInfo.l2Bridge();
        require(l2Bridge != address(0), "l2Bridge not set");

        IPolygonZkEVMBridge bridge = IPolygonZkEVMBridge(l2Bridge);

        address forkonomicToken = chainInfo.getForkonomicToken();

        // The receiving contract may get different payments from different requests
        // To differentiate our payment, we will use a dedicated MoneyBox contract controlled by l1GlobalForkRequester
        // The L1GlobalForkRequester will deploy this as and when it's needed.
        // TODO: For now we assume only 1 request is in-flight at a time. If there might be more, differentiate them in the salt.
        bytes32 salt = keccak256(abi.encodePacked(address(this), question_id));
        address moneyBox = CalculateMoneyBoxAddress._calculateMoneyBoxAddress(
            address(l1GlobalForkRequester),
            salt,
            address(forkonomicToken)
        );

        bytes memory permitData;
        bridge.bridgeAsset{value: forkFee}(
            uint32(0),
            moneyBox,
            forkFee, // TODO: Should this be 0 since we already sent the forkFee as msg.value?
            address(0), // Empty address for the native token
            true,
            permitData
        );

        isForkInProgress = true;
    }

    // If the fork request fails, we will get a message back through the bridge telling us about it
    // We will set FORK_REQUEST_FAILED which will allow anyone to request cancellation
    function onMessageReceived(
        address _originAddress,
        uint32 _originNetwork,
        bytes memory _data
    ) external payable {
        address l2Bridge = chainInfo.l2Bridge();
        require(msg.sender == l2Bridge, "Not our bridge");
        require(_originNetwork == uint32(0), "Wrong network, WTF");
        require(
            _originAddress == address(l1GlobalForkRequester),
            "Unexpected sender"
        );

        bytes32 question_id = bytes32(_data);
        RequestStatus status = arbitrationRequests[question_id].status;
        require(
            status == RequestStatus.FORK_REQUESTED,
            "not in fork-requested state"
        );
        require(isForkInProgress, "No fork in progress to clear");

        isForkInProgress = false;
        arbitrationRequests[question_id].status = RequestStatus
            .FORK_REQUEST_FAILED;

        // We don't check the funds are back here, just assume L1GlobalForkRequester send them and they can be recovered.
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
        require(
            status == RequestStatus.FORK_REQUESTED,
            "not in fork-requested state"
        );

        require(
            chainInfo.questionToChainID(false, address(this), question_id) > 0,
            "Dispute not found in ChainInfo"
        );

        // We get the fork result from the L2ChainInfo contract
        bytes32 answer = chainInfo.forkQuestionResults(
            false,
            address(this),
            question_id
        );

        realitio.assignWinnerAndSubmitAnswerByArbitrator(
            question_id,
            answer,
            arbitrationRequests[question_id].payer,
            last_history_hash,
            last_answer_or_commitment_id,
            last_answerer
        );

        isForkInProgress = false;
        delete (arbitrationRequests[question_id]);
    }

    /// @notice Cancel a previous arbitration request
    /// @dev This is intended for situations where the stuff is happening non-atomically and the fee changes or someone else forks before us
    /// @dev Another way to handle this might be to go back into QUEUED state and let people keep retrying
    /// @dev NB This may revert if the contract has returned funds in the bridge but claimAsset hasn't been called yet
    /// @param question_id The question in question
    function cancelArbitration(bytes32 question_id) external {
        // For simplicity we won't let you cancel until forking is sorted, as you might retry and keep failing for the same reason
        require(!isForkInProgress, "Fork in progress");

        RequestStatus status = arbitrationRequests[question_id].status;
        require(
            status == RequestStatus.FORK_REQUEST_FAILED,
            "Not in fork-failed state"
        );

        address payable payer = arbitrationRequests[question_id].payer;
        realitio.cancelArbitration(question_id);

        refundsDue[payer] =
            refundsDue[payer] +
            arbitrationRequests[question_id].paid;
        delete (arbitrationRequests[question_id]);
    }

    function claimRefund() external {
        uint256 due = refundsDue[msg.sender];
        refundsDue[msg.sender] = refundsDue[msg.sender] - due;
        payable(msg.sender).transfer(due);
    }
}
