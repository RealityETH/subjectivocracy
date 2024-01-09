// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

/* solhint-disable var-name-mixedcase */
/* solhint-disable quotes */
/* solhint-disable not-rely-on-time */

import {IRealityETH} from "./../lib/reality-eth/interfaces/IRealityETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
/*
Minimal Adjudication framework every framework should implement
Contains an iterableList of Arbitrators.
Arbitrators can be frozen by providing a bond and be removed by 
a realityETH question with forking as a final arbitration.
*/

contract MinimalAdjudicationFramework {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet internal arbitrators;
    /// @dev Error thrown when non-allowlisted actor tries to call a function
    error OnlyAllowlistedActor();

    // Iterable list contains list of allowlisted arbitrators
    uint256 public constant ARB_DISPUTE_TIMEOUT = 86400;
    uint256 public constant QUESTION_UNHANDLED_TIMEOUT = 86400;

    uint32 public constant REALITY_ETH_TIMEOUT = 86400;
    uint32 public constant REALITY_ETH_BOND_ARBITRATOR_REMOVE = 10000;
    uint32 public constant REALITY_ETH_BOND_ARBITRATOR_FREEZE = 20000;

    // Template used to remove arbitrators, in case they are misbehaving
    uint256 public templateIdRemoveArbitrator;

    // Contract used for requesting a fork in the L1 chain in remove propositions
    address public forkArbitrator;

    // Propositions to manage arbitrators
    enum PropositionType {
        NONE,
        ADD_ARBITRATOR,
        REMOVE_ARBITRATOR
    }
    // Reality.eth questions for propositions we may be asked to rule on
    struct ArbitratorProposition {
        PropositionType proposition_type;
        address arbitratorToRemove;
        address newArbitrator;
        bool isFrozen;
    }
    mapping(bytes32 => ArbitratorProposition) public propositions;

    // Keep a count of active propositions that freeze an arbitrator.
    // When they're all cleared they can be unfrozen.
    mapping(address => uint256) public countArbitratorFreezePropositions;

    IRealityETH public realityETH;

    modifier onlyArbitrator() {
        if (!arbitrators.contains(msg.sender)) {
            revert OnlyAllowlistedActor();
        }
        _;
    }

    /// @param _realityETH The reality.eth instance we adjudicate for
    /// @param _forkArbitrator The arbitrator contract that escalates to an L1 fork, used for our governance
    /// @param _initialArbitrators Arbitrator contracts we initially support
    constructor(
        address _realityETH,
        address _forkArbitrator,
        address[] memory _initialArbitrators
    ) {
        realityETH = IRealityETH(_realityETH);
        forkArbitrator = _forkArbitrator;

        // Create reality.eth templates for our add and remove questions
        // We'll identify ourselves in the template so we only need a single parameter for questions, the arbitrator in question.
        // TODO: We may want to specify a document with the terms that guide this decision here, rather than just leaving it implicit.
        string
            memory templatePrefixRemove = '{"title": "Should we remove arbitrator %s and replace them by %s from the framework ';
        string
            memory templateSuffix = '?", "type": "bool", "category": "adjudication", "lang": "en"}';

        string memory thisContractStr = Strings.toHexString(address(this));
        string memory removeTemplate = string.concat(
            templatePrefixRemove,
            thisContractStr,
            templateSuffix
        );
        templateIdRemoveArbitrator = realityETH.createTemplate(removeTemplate);

        // Allowlist the initial arbitrators
        for (uint256 i = 0; i < _initialArbitrators.length; i++) {
            arbitrators.add(_initialArbitrators[i]);
        }
    }

    function beginReplaceArbitratorFromAllowList(
        address arbitratorToRemove,
        address replacementArbitrator
    ) external returns (bytes32) {
        string memory question = string(
            abi.encodePacked(
                Strings.toHexString(arbitratorToRemove),
                Strings.toHexString(replacementArbitrator)
            )
        );
        bytes32 questionId = realityETH.askQuestionWithMinBond(
            templateIdRemoveArbitrator,
            question,
            forkArbitrator,
            REALITY_ETH_TIMEOUT,
            uint32(block.timestamp),
            0,
            REALITY_ETH_BOND_ARBITRATOR_REMOVE
        );
        require(
            propositions[questionId].proposition_type == PropositionType.NONE,
            "Proposition already exists"
        );
        propositions[questionId] = ArbitratorProposition(
            PropositionType.REMOVE_ARBITRATOR,
            arbitratorToRemove,
            replacementArbitrator,
            false
        );

        return questionId;
    }

    function executeReplacementArbitratorFromAllowList(
        bytes32 questionId
    ) external {
        require(
            propositions[questionId].proposition_type ==
                PropositionType.REMOVE_ARBITRATOR,
            "Wrong Proposition type"
        );

        // NB This will run even if the arbitrator has already been removed by another proposition.
        // This is needed so that the freeze can be cleared if the arbitrator is then reinstated.

        address arbitratorToRemove = propositions[questionId]
            .arbitratorToRemove;
        address newArbitrator = propositions[questionId].newArbitrator;
        bytes32 realityEthResult = realityETH.resultFor(questionId);
        require(realityEthResult == bytes32(uint256(1)), "Result was not 1");

        arbitrators.remove(arbitratorToRemove);
        if (propositions[questionId].isFrozen) {
            countArbitratorFreezePropositions[arbitratorToRemove] -= 1;
        }
        if (newArbitrator != address(0)) {
            arbitrators.add(newArbitrator);
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
        require(
            propositions[questionId].proposition_type ==
                PropositionType.REMOVE_ARBITRATOR,
            "Wrong Proposition type"
        );
        address arbitrator = propositions[questionId].arbitratorToRemove;

        require(
            arbitrators.contains(arbitrator),
            "Arbitrator not allowlisted" // Not allowlisted in the first place
        );
        require(
            !propositions[questionId].isFrozen,
            "Arbitrator already frozen"
        );

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

        require(answer == bytes32(uint256(1)), "Supplied answer is not yes");
        require(
            bond >= REALITY_ETH_BOND_ARBITRATOR_FREEZE,
            "Bond too low to freeze"
        );

        // TODO: Ideally we would check the bond is for the "remove" answer.
        // #92

        propositions[questionId].isFrozen = true;
        countArbitratorFreezePropositions[arbitrator] =
            countArbitratorFreezePropositions[arbitrator] +
            1;
    }

    function clearFailedProposition(bytes32 questionId) public {
        address arbitrator = propositions[questionId].arbitratorToRemove;
        require(arbitrator != address(0), "Proposition not found");
        if (propositions[questionId].isFrozen) {
            countArbitratorFreezePropositions[arbitrator] =
                countArbitratorFreezePropositions[arbitrator] -
                1;
        }
        delete (propositions[questionId]);
    }

    function realitio() external view returns (address) {
        return address(realityETH);
    }

    function isArbitrator(address arbitrator) external view returns (bool) {
        return arbitrators.contains(arbitrator);
    }
}
