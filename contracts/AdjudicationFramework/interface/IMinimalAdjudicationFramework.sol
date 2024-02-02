// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

/* solhint-disable quotes */
/* solhint-disable not-rely-on-time */

import {IRealityETH} from "./../../lib/reality-eth/interfaces/IRealityETH.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IL2ForkArbitrator} from "../../interfaces/IL2ForkArbitrator.sol";
import {IMinimalAdjudicationFrameworkErrors} from "./IMinimalAdjudicationFrameworkErrors.sol";
/*
Minimal Adjudication framework every framework should implement.
Contains an enumerableSet of Arbitrators.
Arbitrators can be removed or added by providing a realityETH question with forking as a final arbitration.
Also, arbitrators who are challenged by a removal question, can be temporarily frozen, if a sufficient bond is provided.
*/

interface IMinimalAdjudicationFramework is IMinimalAdjudicationFrameworkErrors {
    // Reality.eth questions for propositions we may be asked to rule on
    struct ArbitratorProposition {
        address arbitratorToRemove;
        address arbitratorToAdd;
        bool isFrozen;
    }

    function requestModificationOfArbitrators(
        address arbitratorToRemove,
        address arbitratorToAdd
    ) external returns (bytes32);

    function executeModificationArbitratorFromAllowList(
        bytes32 questionId
    ) external;

    // When an arbitrator is listed for removal, they can be frozen given a sufficient bond
    function freezeArbitrator(
        bytes32 questionId,
        bytes32[] memory historyHashes,
        address[] memory addrs,
        uint256[] memory bonds,
        bytes32[] memory answers
    ) external;

    function clearFailedProposition(bytes32 questionId) external;

    // Getter functions only below here

    function realitio() external view returns (address);

    function isArbitrator(address arbitrator) external view returns (bool);

    function isArbitratorPropositionFrozen(
        bytes32 questionId
    ) external view returns (bool);

    function getInvestigationDelay() external view returns (uint256);
}
