// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

/* solhint-disable quotes */
/* solhint-disable not-rely-on-time */

import {IRealityETH} from "./../lib/reality-eth/interfaces/IRealityETH.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IL2ForkArbitrator} from "../interfaces/IL2ForkArbitrator.sol";
/*
Minimal Adjudication framework every framework should implement.
Contains an enumerableSet of Arbitrators.
Arbitrators can be removed or added by providing a realityETH question with forking as a final arbitration.
Also, arbitrators who are challenged by a removal question, can be temporarily frozen, if a sufficient bond is provided.
*/

contract MinimalAdjudicationFramework {
    using EnumerableSet for EnumerableSet.AddressSet;
    /// @dev Error thrown with illegal modification of arbitrators
    error NoArbitratorsToModify();
    /// @dev Error thrown when a proposition already exists
    error PropositionAlreadyExists();
    /// @dev Error thrown when a proposition is not found
    error PropositionNotFound();
    /// @dev Error thrown when a proposition is not found
    error ArbitratorNotInAllowList();
    /// @dev Error thrown when an arbitrator is already frozen
    error ArbitratorAlreadyFrozen();
    /// @dev Error thrown when received messages from realityEth is not yes
    error AnswerNotYes();
    /// @dev Error thrown when received messages from realityEth is yes, but expected to be no
    error PropositionNotFailed();
    /// @dev Error thrown when bond is too low to freeze an arbitrator
    error BondTooLowToFreeze();
    /// @dev Error thrown when proposition is not accepted
    error PropositionNotAccepted();

    // Question delimiter for arbitrator modification questions for reality.eth
    string internal constant _QUESTION_DELIM = "\u241f";

    EnumerableSet.AddressSet internal _arbitrators;
    /// @dev Error thrown when non-allowlisted actor tries to call a function
    error OnlyAllowlistedActor();
    /// @dev Error thrown when multiple modifications are requested at once
    error NoMultipleModificationsAtOnce();

    // Iterable list contains list of allowlisted arbitrators
    uint256 public constant ARB_DISPUTE_TIMEOUT = 86400;
    uint256 public constant QUESTION_UNHANDLED_TIMEOUT = 86400;

    uint32 public constant REALITY_ETH_TIMEOUT = 86400;
    uint32 public constant REALITY_ETH_BOND_ARBITRATOR_REMOVE = 10000;
    uint32 public constant REALITY_ETH_BOND_ARBITRATOR_FREEZE = 20000;

    // Template used to remove arbitrators, in case they are misbehaving
    uint256 public templateIdRemoveArbitrator;
    uint256 public templateIdAddArbitrator;
    uint256 public templateIdReplaceArbitrator;

    bool public allowReplacementModification;

    // Contract used for requesting a fork in the L1 chain in remove propositions
    address public forkArbitrator;

    // Reality.eth questions for propositions we may be asked to rule on
    struct ArbitratorProposition {
        address arbitratorToRemove;
        address arbitratorToAdd;
        bool isFrozen;
    }
    mapping(bytes32 => ArbitratorProposition) public propositions;

    // Keep a count of active propositions that freeze an arbitrator.
    // When they're all cleared they can be unfrozen.
    mapping(address => uint256) public countArbitratorFreezePropositions;

    uint256 public arbitrationDelayForCollectingEvidence;
    IRealityETH public realityETH;

    modifier onlyArbitrator() {
        if (!_arbitrators.contains(msg.sender)) {
            revert OnlyAllowlistedActor();
        }
        _;
    }

    /// @param _realityETH The reality.eth instance we adjudicate for
    /// @param _forkArbitrator The arbitrator contract that escalates to an L1 fork, used for our governance
    /// @param _initialArbitrators Arbitrator contracts we initially support
    /// @param _allowReplacementModification Whether to allow multiple modifications at once
    /// @param _arbitrationDelayForCollectingEvidence The delay before arbitration can be requested
    constructor(
        address _realityETH,
        address _forkArbitrator,
        address[] memory _initialArbitrators,
        bool _allowReplacementModification,
        uint256 _arbitrationDelayForCollectingEvidence
    ) {
        allowReplacementModification = _allowReplacementModification;
        realityETH = IRealityETH(_realityETH);
        forkArbitrator = _forkArbitrator;
        arbitrationDelayForCollectingEvidence = _arbitrationDelayForCollectingEvidence;
        // Create reality.eth templates for our add questions
        // We'll identify ourselves in the template so we only need a single parameter for questions, the arbitrator in question.
        // TODO: We may want to specify a document with the terms that guide this decision here, rather than just leaving it implicit.
        string
            memory templatePrefixReplace = '{"title": "Should we replace the arbitrator %s by the new arbitrator %s in the framework ';
        string
            memory templatePrefixAdd = '{"title": "Should we add the arbitrator %s to the framework ';
        string
            memory templatePrefixRemove = '{"title": "Should we remove the arbitrator %s from the framework ';
        string
            memory templateSuffix = '?", "type": "bool", "category": "adjudication", "lang": "en"}';
        string memory thisContractStr = Strings.toHexString(address(this));
        string memory removeTemplate = string.concat(
            templatePrefixRemove,
            thisContractStr,
            templateSuffix
        );
        string memory addTemplate = string.concat(
            templatePrefixAdd,
            thisContractStr,
            templateSuffix
        );
        string memory replaceTemplate = string.concat(
            templatePrefixReplace,
            thisContractStr,
            templateSuffix
        );
        templateIdRemoveArbitrator = realityETH.createTemplate(removeTemplate);
        templateIdAddArbitrator = realityETH.createTemplate(addTemplate);
        templateIdReplaceArbitrator = realityETH.createTemplate(
            replaceTemplate
        );

        // Allowlist the initial arbitrators
        for (uint256 i = 0; i < _initialArbitrators.length; i++) {
            _arbitrators.add(_initialArbitrators[i]);
        }
    }

    function requestModificationOfArbitrators(
        address arbitratorToRemove,
        address arbitratorToAdd
    ) external returns (bytes32) {
        string memory question;
        uint256 templateId;
        if (arbitratorToRemove == address(0) && arbitratorToAdd == address(0)) {
            revert NoArbitratorsToModify();
        } else if (arbitratorToRemove == address(0)) {
            question = Strings.toHexString(arbitratorToAdd);
            templateId = templateIdAddArbitrator;
        } else if (arbitratorToAdd == address(0)) {
            question = Strings.toHexString(arbitratorToRemove);
            templateId = templateIdRemoveArbitrator;
        } else {
            if (!allowReplacementModification) {
                revert NoMultipleModificationsAtOnce();
            }
            question = string.concat(
                Strings.toHexString(arbitratorToRemove),
                _QUESTION_DELIM,
                Strings.toHexString(arbitratorToAdd)
            );
            templateId = templateIdReplaceArbitrator;
        }
        bytes32 questionId = realityETH.askQuestionWithMinBond(
            templateId,
            question,
            forkArbitrator,
            REALITY_ETH_TIMEOUT,
            uint32(block.timestamp),
            0,
            REALITY_ETH_BOND_ARBITRATOR_REMOVE
        );
        IL2ForkArbitrator(forkArbitrator).storeInformation(
            templateId,
            uint32(block.timestamp),
            question,
            REALITY_ETH_TIMEOUT,
            REALITY_ETH_BOND_ARBITRATOR_REMOVE,
            0,
            arbitrationDelayForCollectingEvidence
        );
        if (
            propositions[questionId].arbitratorToAdd != address(0) ||
            propositions[questionId].arbitratorToRemove != address(0)
        ) {
            revert PropositionAlreadyExists();
        }
        propositions[questionId] = ArbitratorProposition(
            arbitratorToRemove,
            arbitratorToAdd,
            false
        );
        return questionId;
    }

    function executeModificationArbitratorFromAllowList(
        bytes32 questionId
    ) external {
        // NB This will run even if the arbitrator has already been removed by another proposition.
        // This is needed so that the freeze can be cleared if the arbitrator is then reinstated.

        address arbitratorToRemove = propositions[questionId]
            .arbitratorToRemove;
        address arbitratorToAdd = propositions[questionId].arbitratorToAdd;
        bytes32 realityEthResult = realityETH.resultFor(questionId);
        if (realityEthResult != bytes32(uint256(1))) {
            revert PropositionNotAccepted();
        }
        if (arbitratorToRemove != address(0)) {
            _arbitrators.remove(arbitratorToRemove);
            if (propositions[questionId].isFrozen) {
                countArbitratorFreezePropositions[arbitratorToRemove] -= 1;
            }
        }
        if (arbitratorToAdd != address(0)) {
            _arbitrators.add(arbitratorToAdd);
        }
        delete (propositions[questionId]);
    }

    // When an arbitrator is listed for removal, they can be frozen given a sufficient bond
    function freezeArbitrator(
        bytes32 questionId,
        bytes32[] memory historyHashes,
        address[] memory addrs,
        uint256[] memory bonds,
        bytes32[] memory answers
    ) public {
        address arbitrator = propositions[questionId].arbitratorToRemove;

        if (arbitrator == address(0)) {
            revert PropositionNotFound();
        }
        if (!_arbitrators.contains(arbitrator)) {
            revert ArbitratorNotInAllowList();
        }
        if (propositions[questionId].isFrozen) {
            revert ArbitratorAlreadyFrozen();
        }

        // Require a bond of at least the specified level
        // This is only relevant if REALITY_ETH_BOND_ARBITRATOR_FREEZE is higher than REALITY_ETH_BOND_ARBITRATOR_REMOVE

        bytes32 answer;
        uint256 bond;
        // Normally you call this right after posting your answer so your final answer will be the current answer
        // If someone has since submitted a different answer, you need to pass in the history from now until yours
        if (historyHashes.length == 0) {
            answer = realityETH.getBestAnswer(questionId);
            bond = realityETH.getBond(questionId);
        } else {
            (answer, bond) = realityETH
                .getEarliestAnswerFromSuppliedHistoryOrRevert(
                    questionId,
                    historyHashes,
                    addrs,
                    bonds,
                    answers
                );
        }

        if (answer != bytes32(uint256(1))) {
            revert AnswerNotYes();
        }
        if (bond < REALITY_ETH_BOND_ARBITRATOR_FREEZE) {
            revert BondTooLowToFreeze();
        }

        // TODO: Ideally we would check the bond is for the "remove" answer.
        // #92

        propositions[questionId].isFrozen = true;
        countArbitratorFreezePropositions[arbitrator] =
            countArbitratorFreezePropositions[arbitrator] +
            1;
    }

    function clearFailedProposition(bytes32 questionId) public {
        address arbitrator = propositions[questionId].arbitratorToRemove;
        if (arbitrator == address(0)) {
            revert PropositionNotFound();
        }

        bytes32 realityEthResult = realityETH.resultFor(questionId);
        if (realityEthResult == bytes32(uint256(1))) {
            revert PropositionNotFailed();
        }
        if (propositions[questionId].isFrozen) {
            countArbitratorFreezePropositions[arbitrator] =
                countArbitratorFreezePropositions[arbitrator] -
                1;
        }
        delete (propositions[questionId]);
    }

    // Getter functions only below here

    function realitio() external view returns (address) {
        return address(realityETH);
    }

    function isArbitrator(address arbitrator) external view returns (bool) {
        return _arbitrators.contains(arbitrator);
    }

    function isArbitratorPropositionFrozen(
        bytes32 questionId
    ) external view returns (bool) {
        return propositions[questionId].isFrozen;
    }
}
