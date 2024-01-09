// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

/* solhint-disable quotes */
/* solhint-disable not-rely-on-time */

import {BalanceHolder} from "./../lib/reality-eth/BalanceHolder.sol";

import {IRealityETH} from "./../lib/reality-eth/interfaces/IRealityETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Requests} from "./Pull/Requests.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/*
This contract sits between a Reality.eth instance and an Arbitrator.
It manages a allowlist of arbitrators, and makes sure questions can be sent to an arbitrator on the allowlist.
When called on to arbitrate, it pays someone to send out the arbitration job to an arbitrator on the allowlist.
Arbitrators can be disputed on L1.
To Reality.eth it looks like a normal arbitrator, implementing the Arbitrator interface.
To the normal Arbitrator contracts that does its arbitration jobs, it looks like Reality.eth.
*/

contract AdjudicationFramework is Requests {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint32 public constant REALITY_ETH_BOND_ARBITRATOR_ADD = 10000;

    uint256 public templateIdAddArbitrator;

    /// @param _realityETH The reality.eth instance we adjudicate for
    /// @param _disputeFee The dispute fee we charge reality.eth users
    /// @param _forkArbitrator The arbitrator contract that escalates to an L1 fork, used for our governance
    /// @param _initialArbitrators Arbitrator contracts we initially support
    constructor(
        address _realityETH,
        uint256 _disputeFee,
        address _forkArbitrator,
        address[] memory _initialArbitrators
    ) Requests(_realityETH, _disputeFee, _forkArbitrator, _initialArbitrators) {
        // Create reality.eth templates for our add questions
        // We'll identify ourselves in the template so we only need a single parameter for questions, the arbitrator in question.
        // TODO: We may want to specify a document with the terms that guide this decision here, rather than just leaving it implicit.
        string
            memory templatePrefixAdd = '{"title": "Should we add arbitrator %s to the framework ';
        string
            memory templateSuffix = '?", "type": "bool", "category": "adjudication", "lang": "en"}';

        string memory thisContractStr = Strings.toHexString(address(this));
        string memory addTemplate = string.concat(
            templatePrefixAdd,
            thisContractStr,
            templateSuffix
        );

        templateIdAddArbitrator = realityETH.createTemplate(addTemplate);
    }

    // Governance (specifically adding and removing arbitrators from the allowlist) has two steps:
    // 1) Create question
    // 2) Complete operation (if proposition succeeded) or nothing if it failed
    // For time-sensitive operations, we also freeze any interested parties, so
    // 1) Create question
    // 2) Prove sufficient bond posted, freeze
    // 3) Complete operation or Undo freeze
    function beginAddArbitratorToAllowList(
        address arbitratorToAdd
    ) external returns (bytes32) {
        string memory question = Strings.toHexString(arbitratorToAdd);
        bytes32 questionId = realityETH.askQuestionWithMinBond(
            templateIdAddArbitrator,
            question,
            forkArbitrator,
            REALITY_ETH_TIMEOUT,
            uint32(block.timestamp),
            0,
            REALITY_ETH_BOND_ARBITRATOR_ADD
        );
        require(
            propositions[questionId].proposition_type == PropositionType.NONE,
            "Proposition already exists"
        );
        propositions[questionId] = ArbitratorProposition(
            PropositionType.ADD_ARBITRATOR,
            address(0),
            arbitratorToAdd,
            false
        );
        return questionId;
    }

    function executeAddArbitratorToAllowList(bytes32 questionId) external {
        require(
            propositions[questionId].proposition_type ==
                PropositionType.ADD_ARBITRATOR,
            "Wrong Proposition type"
        );
        address arbitrator = propositions[questionId].newArbitrator;
        require(
            !arbitrators.contains(arbitrator),
            "Arbitrator already on allowlist"
        );
        require(
            realityETH.resultFor(questionId) == bytes32(uint256(1)),
            "Question did not return yes"
        );
        delete (propositions[questionId]);

        // NB They may still be in a frozen state because of some other proposition
        arbitrators.add(arbitrator);
    }
}
