// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

/*
This is a very limited Arbitrator contract for the purpose of handling an arbitration request and passing it on to the ForkingManager.
It doesn't handle submitting the answer to the winning question, this is instead handled by the child reality.eth contract when forking.
*/

import {IRealityETH} from "@reality.eth/contracts/development/contracts/IRealityETH.sol";
import {IArbitratorCore} from "@reality.eth/contracts/development/contracts/IArbitratorCore.sol";
import {IArbitratorErrors} from "@reality.eth/contracts/development/contracts/IArbitratorErrors.sol";
import {IForkingManager} from "./interfaces/IForkingManager.sol";
import {IForkonomicToken} from "./interfaces/IForkonomicToken.sol";
import {IForkableStructure} from "./interfaces/IForkableStructure.sol";

contract L1ForkArbitrator is IArbitratorCore, IArbitratorErrors {
    IForkingManager public forkmanager;
    IRealityETH public realitio;
    IForkonomicToken public token;

    /// @notice Could not deduct fee
    error CouldNotDeductFee();

    /// @notice Not forked yet
    error NotForkedYet();

    /// @notice This arbitrator can only arbitrate one dispute in its lifetime
    error CanOnlyArbitrateOneDispute();

    /// @notice The question ID must be supplied
    error MissingQuestionID();

    bytes32 public arbitratingQuestionId;
    address public payer;

    constructor(address _realitio, address _forkmanager, address _token) {
        realitio = IRealityETH(_realitio);
        forkmanager = IForkingManager(_forkmanager);
        token = IForkonomicToken(_token);
    }

    /* solhint-disable quotes */
    string public metadata = '{"erc20": true}';

    /// @notice Return the dispute fee for the specified question. 0 indicates that we won't arbitrate it.
    /// @dev Uses a general default, but can be over-ridden on a question-by-question basis.
    function getDisputeFee(bytes32) public view returns (uint256) {
        return forkmanager.arbitrationFee();
    }

    /// @notice Request arbitration, freezing the question until we send submitAnswerByArbitrator
    /// @dev Requires payment in token(), which the UI as of early 2024 will not handle.
    /// @param _questionId The question in question
    /// @param _maxPrevious If specified, reverts if a bond higher than this was submitted after you sent your transaction.
    /// NB TODO: This is payable because the interface expects native tokens. Consider changing the interface or adding an ERC20 version.
    function requestArbitration(
        bytes32 _questionId,
        uint256 _maxPrevious
    ) external payable returns (bool) {
        if (arbitratingQuestionId != bytes32(0))
            revert CanOnlyArbitrateOneDispute();
        if (_questionId == bytes32(0)) revert MissingQuestionID();

        uint256 fee = getDisputeFee(_questionId);
        if (fee == 0)
            revert TheArbitratorMustHaveSetANonZeroFeeForTheQuestion();

        // First we transfer the fee to ourselves.
        if (!token.transferFrom(msg.sender, address(this), fee))
            revert CouldNotDeductFee();

        payer = msg.sender;
        arbitratingQuestionId = _questionId;

        realitio.notifyOfArbitrationRequest(
            _questionId,
            msg.sender,
            _maxPrevious
        );

        // Now approve so that the fee can be transferred right out to the ForkingManager
        if (!token.approve(address(forkmanager), fee))
            revert CouldNotDeductFee();
        IForkingManager.DisputeData memory disputeData = IForkingManager
            .DisputeData(true, address(this), _questionId);
        IForkingManager(forkmanager).initiateFork(disputeData);

        return true;
    }

    function settleChildren(
        bytes32 lastHistoryHash,
        bytes32 lastAnswer,
        address lastAnswerer
    ) public {
        (address child1, address child2) = IForkableStructure(address(realitio))
            .getChildren();
        if (child1 == address(0) || child2 == address(0)) revert NotForkedYet();
        IRealityETH(child1).assignWinnerAndSubmitAnswerByArbitrator(
            arbitratingQuestionId,
            bytes32(uint256(1)),
            payer,
            lastHistoryHash,
            lastAnswer,
            lastAnswerer
        );
        IRealityETH(child2).assignWinnerAndSubmitAnswerByArbitrator(
            arbitratingQuestionId,
            bytes32(uint256(0)),
            payer,
            lastHistoryHash,
            lastAnswer,
            lastAnswerer
        );
    }
}
