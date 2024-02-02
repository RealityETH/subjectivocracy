// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

/* solhint-disable quotes */
/* solhint-disable not-rely-on-time */

import {IMinimalAdjudicationFrameworkErrors} from "./IMinimalAdjudicationFrameworkErrors.sol";

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
