// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

import {Feeds} from "./Push/Feeds.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/** 
Feeds arbitration framework, which allows arbitrators to manage themselves.
*/

contract AdjudicationFrameworkForFeedsWithSelfManagement is Feeds {
    using EnumerableSet for EnumerableSet.AddressSet;
    /// @param _realityETH The reality.eth instance we adjudicate for
    /// @param _forkArbitrator The arbitrator contract that escalates to an L1 fork, used for our governance
    /// @param _initialArbitrators Arbitrator contracts we initially support
    constructor(
        address _realityETH,
        address _forkArbitrator,
        address[] memory _initialArbitrators
    ) Feeds(_realityETH, _forkArbitrator, _initialArbitrators) {}

    /**
    @dev Allows an arbitrator to add another arbitrator to the allowlist
     */
    function addArbitrator(address arbitrator) external onlyArbitrator {
        arbitrators.add(arbitrator);
    }

    /**
    @dev Allows an arbitrator to remove another arbitrator from the allowlist
     */
    function removeArbitrator(address arbitrator) external onlyArbitrator {
        arbitrators.remove(arbitrator);
    }
}
