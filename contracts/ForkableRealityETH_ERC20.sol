// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

import {RealityETHFreezable_ERC20} from "@reality.eth/contracts/development/contracts/RealityETHFreezable_ERC20.sol";
import {ForkableStructure} from "./mixin/ForkableStructure.sol";

import {IERC20} from "@reality.eth/contracts/development/contracts/IERC20.sol";
import {IForkonomicToken} from "./interfaces/IForkonomicToken.sol";

import {IForkableRealityETH_ERC20} from "./interfaces/IForkableRealityETH_ERC20.sol";
import {L1ForkArbitrator} from "./L1ForkArbitrator.sol";

/*
This is a forkable version of the Reality.eth contract for use on L1.
*/

contract ForkableRealityETH_ERC20 is
    RealityETHFreezable_ERC20,
    ForkableStructure
{
    // Asking questions is locked down the the forkmanager.
    // This isn't strictly necessary but it reduces the attack surface.
    // TODO: We might want to replace this with a governance contract owned by the forkmanager.
    modifier permittedQuestionerOnly() override {
        if (msg.sender != forkmanager) revert PermittedQuestionerOnly();
        _;
    }

    // This arbitrator is assigned automatically when importing questions
    address public l1ForkArbitrator;

    uint256 constant UPGRADE_TEMPLATE_ID = 1048576;

    function initialize(
        address _forkmanager,
        address _parentContract,
        address _token,
        bytes32 _questionIdWeForkedOver
    ) public initializer {
        // We do this with a new contract instead of a proxy as it's pretty tiny
        // TODO: Should we use a proxy pattern like elsewhere?
        l1ForkArbitrator = address(
            new L1ForkArbitrator(
                address(this),
                address(_forkmanager),
                address(_token)
            )
        );

        ForkableStructure.initialize(_forkmanager, _parentContract);

        _createInitialTemplates();
        token = IERC20(_token);

        // We immediately import the initial question we forked over, which keep its original arbitrator.
        // (Any other imported question will use the new l1ForkArbitrator)
        if (_questionIdWeForkedOver != bytes32(0x0)) {
            address parentArbitrator = ForkableRealityETH_ERC20(parentContract)
                .l1ForkArbitrator();
            _importQuestion(_questionIdWeForkedOver, parentArbitrator);
        }
    }

    function _createInitialTemplates() internal override {
        // TODO: Decide if we want to include the original templates for consistency/flexibility
        // ...even though they won't be used unless we upgrade the forkmanager or whatever governs this.

        // Bump the next template ID to stay clear of the range of the normal stock templates, as this might confuse the UI
        nextTemplateID = UPGRADE_TEMPLATE_ID;
        createTemplate(
            '{"title": "Should we execute the upgrade contract %s?", "type": "bool"}'
        );
    }

    /// Copies a question from an old instance to this new one after a fork
    /// The budget for this question should have been transferred when we did the fork.
    /// We won't delete the question on the parent reality.eth contract, but you won't be able to do anything with it because it'll be frozen.
    /// NB The question ID will no longer match the hash of the content, as the arbitrator has changed
    /// @param _questionId - The ID of the question to import
    /// @param _newArbitrator - The new arbitrator we should use.
    function _importQuestion(
        bytes32 _questionId,
        address _newArbitrator
    ) internal {
        IForkableRealityETH_ERC20 parent = IForkableRealityETH_ERC20(
            parentContract
        );
        uint32 timeout = parent.getTimeout(_questionId);
        uint32 finalizeTS = parent.getFinalizeTS(_questionId);
        bool isPendingArbitration = parent.isPendingArbitration(_questionId);

        // For any open question, bump the finalization time to the import time plus a normal timeout period.
        if (
            finalizeTS > 0 &&
            !isPendingArbitration &&
            !parent.isFinalized(_questionId)
        ) {
            finalizeTS = uint32(block.timestamp + timeout);
        }

        questions[_questionId] = Question(
            parent.getContentHash(_questionId),
            _newArbitrator,
            parent.getOpeningTS(_questionId),
            timeout,
            finalizeTS,
            isPendingArbitration,
            parent.getBounty(_questionId),
            parent.getBestAnswer(_questionId),
            parent.getHistoryHash(_questionId),
            parent.getBond(_questionId),
            parent.getMinBond(_questionId)
        );
    }

    // Anyone can import any question if it has not already been imported.
    function importQuestion(
        bytes32 questionId
    ) external stateNotCreated(questionId) {
        _importQuestion(questionId, l1ForkArbitrator);
    }

    function createChildren()
        external
        onlyForkManger
        returns (address, address)
    {
        return _createChildren();
    }

    // Move our internal balance record for a single address to the child contracts after a fork.
    function moveBalanceToChildren(
        address beneficiary
    ) external onlyAfterForking {
        uint256 bal = balanceOf[beneficiary];
        balanceOf[beneficiary] = 0;
        IForkableRealityETH_ERC20(children[0]).creditBalanceFromParent(
            beneficiary,
            bal
        );
        IForkableRealityETH_ERC20(children[1]).creditBalanceFromParent(
            beneficiary,
            bal
        );
    }

    function creditBalanceFromParent(
        address beneficiary,
        uint256 amount
    ) external onlyParent {
        balanceOf[beneficiary] = balanceOf[beneficiary] + amount;
    }

    function _moveTokensToChild(
        address _childRealityETH,
        uint256 amount
    ) internal {
        address childToken = address(
            IForkableRealityETH_ERC20(_childRealityETH).token()
        );
        IForkonomicToken(childToken).transfer(_childRealityETH, amount);
    }

    // TODO: Make sure this gets called on initiateFork, it can't wait until executeFork because we can't arbitrate anything else that happens
    // It may be simpler to let anybody call it and have it check with the fork manager that we're forking
    function handleFork() external onlyForkManger onlyAfterForking {
        uint256 balance = token.balanceOf(address(this));
        IForkonomicToken(address(token)).splitTokensIntoChildTokens(balance);
        _moveTokensToChild(children[0], balance);
        _moveTokensToChild(children[1], balance);
        freezeTs = uint32(block.timestamp);
    }
}
