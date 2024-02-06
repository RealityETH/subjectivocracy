// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

// Allow mixed-case variables for compatibility with reality.eth, eg it uses question_id not questionId
/* solhint-disable var-name-mixedcase */
import {L2ChainInfo} from "./L2ChainInfo.sol";
import {L1GlobalForkRequester} from "./L1GlobalForkRequester.sol";
import {IRealityETH} from "./lib/reality-eth/interfaces/IRealityETH.sol";
import {CalculateMoneyBoxAddress} from "./lib/CalculateMoneyBoxAddress.sol";

import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {IL2ForkArbitrator} from "./interfaces/IL2ForkArbitrator.sol";
import {IMinimalAdjudicationFramework} from "./AdjudicationFramework/interface/IMinimalAdjudicationFramework.sol";
/*
This contract is the arbitrator used by governance propositions for AdjudicationFramework contracts.
It charges a dispute fee of 5% of total supply [TODO], which it forwards to L1 when requesting a fork.
If there is already a dispute in progress (ie another fork has been requested but not yet triggered or 
we are in the 1 week period before a fork) the new one will be queued.
*/

// NB This doesn't implement IArbitrator because that requires slightly more functions than we need
// TODO: Would be good to make a stripped-down IArbitrator that only has the essential functions
contract L2ForkArbitrator is IL2ForkArbitrator {
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
        uint256 timeOfRequest;
    }

    event LogRequestArbitration(
        bytes32 indexed question_id,
        uint256 fee_paid,
        address requester,
        uint256 remaining
    );

    // stores data on the arbitration process
    // questionId => ArbitrationRequest
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

    /// @inheritdoc IL2ForkArbitrator
    function getDisputeFee(bytes32) public view returns (uint256) {
        return disputeFee;
    }

    /// @inheritdoc IL2ForkArbitrator
    function requestArbitration(
        bytes32 questionId,
        uint256 maxPrevious
    ) external payable returns (bool) {
        uint256 arbitration_fee = getDisputeFee(questionId);
        if (arbitration_fee == 0) {
            revert ArbitrationFeeMustBePositive();
        }
        if (arbitrationRequests[questionId].status != RequestStatus.NONE) {
            revert ArbitrationAlreadyRequested();
        }

        uint256 timeOfFirstRequest = arbitrationRequests[questionId]
            .timeOfRequest == 0
            ? block.timestamp
            : arbitrationRequests[questionId].timeOfRequest;
        arbitrationRequests[questionId] = ArbitrationRequest(
            RequestStatus.QUEUED,
            payable(msg.sender),
            msg.value,
            bytes32(0),
            timeOfFirstRequest
        );

        realitio.notifyOfArbitrationRequest(
            questionId,
            msg.sender,
            maxPrevious
        );
        emit LogRequestArbitration(questionId, msg.value, msg.sender, 0);
        return true;
    }

    /// @inheritdoc IL2ForkArbitrator
    // @note This function requires all the information from the original question,
    // to verify the address of the adjudication framework that initially asked the question
    // With the address of the adjudication framework, we can get the investigation delay
    function requestActivateFork(
        uint256 templateId,
        uint32 openingTs,
        string calldata question,
        uint32 timeout,
        uint256 minBond,
        uint256 nonce,
        address adjudicationFramework
    ) public {
        bytes32 contentHash = keccak256(
            abi.encodePacked(templateId, openingTs, question)
        );
        bytes32 question_id = keccak256(
            abi.encodePacked(
                contentHash,
                address(this),
                timeout,
                minBond,
                address(realitio),
                adjudicationFramework,
                nonce
            )
        );
        uint256 delay = IMinimalAdjudicationFramework(adjudicationFramework)
            .getInvestigationDelay();

        if (
            arbitrationRequests[question_id].timeOfRequest + delay >
            block.timestamp
        ) revert RequestStillInWaitingPeriod();

        if (isForkInProgress) {
            revert ForkInProgress(); // Forking over something else
        }

        if (
            arbitrationRequests[question_id].status ==
            RequestStatus.FORK_REQUEST_FAILED &&
            msg.sender != arbitrationRequests[question_id].payer
        ) {
            // If the fork request is done for the first time, anyone can call it. This ensures that a request will be processed even if the original payer is not available.
            // Though, if the fork request failed, only the original payer can reinitiate it.
            revert WrongSender();
        }

        RequestStatus status = arbitrationRequests[question_id].status;
        if (
            status != RequestStatus.QUEUED &&
            status != RequestStatus.FORK_REQUEST_FAILED
        ) {
            revert NotAwaitingActivation();
        }
        arbitrationRequests[question_id].status = RequestStatus.FORK_REQUESTED;

        uint256 forkFee = chainInfo.getForkFee();
        uint256 paid = arbitrationRequests[question_id].paid;
        if (paid < forkFee) {
            revert ArbitrationFeeMustBePositive();
        }

        address l2Bridge = chainInfo.l2Bridge();
        if (l2Bridge == address(0)) {
            revert L2BridgeNotSet();
        }

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
            forkFee, // must be equal to msg.value
            address(0), // Empty address for the native token
            true,
            permitData
        );

        isForkInProgress = true;
    }

    /// @inheritdoc IL2ForkArbitrator
    function onMessageReceived(
        address _originAddress,
        uint32 _originNetwork,
        bytes memory _data
    ) external payable {
        address l2Bridge = chainInfo.l2Bridge();
        if (msg.sender != l2Bridge) {
            revert WrongBridge();
        }
        if (_originNetwork != uint32(0)) {
            revert WrongNetwork();
        }
        if (_originAddress != address(l1GlobalForkRequester)) {
            revert WrongSender();
        }

        bytes32 question_id = bytes32(_data);
        RequestStatus status = arbitrationRequests[question_id].status;
        if (status != RequestStatus.FORK_REQUESTED) {
            revert WrongStatus();
        }
        if (!isForkInProgress) {
            revert ForkNotInProgress();
        }

        isForkInProgress = false;
        arbitrationRequests[question_id].status = RequestStatus
            .FORK_REQUEST_FAILED;

        realitio.cancelArbitration(question_id);
        address payable payer = arbitrationRequests[question_id].payer;

        refundsDue[payer] =
            refundsDue[payer] +
            arbitrationRequests[question_id].paid;
        deleteArbitrationRequestsData(question_id);
        // We don't check the funds are back here, just assume L1GlobalForkRequester send them and they can be recovered.
    }

    /// @inheritdoc IL2ForkArbitrator
    function handleCompletedFork(
        bytes32 question_id,
        bytes32 last_history_hash,
        bytes32 last_answer_or_commitment_id,
        address last_answerer
    ) external {
        // Read from directory what the result was
        RequestStatus status = arbitrationRequests[question_id].status;
        if (status != RequestStatus.FORK_REQUESTED) {
            revert StatusNotForkRequested();
        }
        if (
            chainInfo.questionToChainID(false, address(this), question_id) == 0
        ) {
            revert QuestionNotForked();
        }

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

    /// @inheritdoc IL2ForkArbitrator
    function cancelArbitration(bytes question_id)external {
        RequestStatus arbitrationStatus = arbitrationRequests[question_id].status;
        if (arbitrationStatus != RequestStatus.QUEUED) {
            revert NotAwaitingActivation();
        }

        uint256 forkFee = chainInfo.getForkFee();
        uint256 paid = arbitrationRequests[question_id].paid;
        if (paid >= forkFee) {
            // We only allow the cancellation if the fee is not enough to trigger the fork
            // due to a fee modification happening after the arbitration request
            revert ArbitrationCanNotBeCanceled();
        }
        realitio.cancelArbitration(question_id);
        address payable payer = arbitrationRequests[question_id].payer;

        refundsDue[payer] =
            refundsDue[payer] +
            arbitrationRequests[question_id].paid;
        deleteArbitrationRequestsData(question_id);
    }

    function deleteArbitrationRequestsData(bytes32 question_id) internal {
        arbitrationRequests[question_id].status = RequestStatus.NONE;
        // the following data does not need to be deleted, and with the new removal of restore opcode, we could leave them as they are.
        arbitrationRequests[question_id].payer = payable(address(0));
        arbitrationRequests[question_id].paid = 0;
        arbitrationRequests[question_id].result = bytes32(0);
        // we don't delete the timeOfRequest on purpose because it will be relevant for the next request
    }

    function claimRefund() external {
        uint256 due = refundsDue[msg.sender];
        refundsDue[msg.sender] = refundsDue[msg.sender] - due;
        payable(msg.sender).transfer(due);
    }
}
