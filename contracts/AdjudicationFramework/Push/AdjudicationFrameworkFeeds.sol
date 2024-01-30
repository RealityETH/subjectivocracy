// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

/* solhint-disable not-rely-on-time */

import {MinimalAdjudicationFramework} from "./../MinimalAdjudicationFramework.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/*
This contract is an example contract to govern price feeds using the backstop's arbitration framework.
The feed is stored as an _arbitrator and can be exchanged using the backstop forking method.
*/

// Interface copied from here:
// https://github.com/chronicleprotocol/OracleReader-Example/blob/main/src/IChronicle.sol

interface IChronicle {
    /// @notice Returns the oracle's current value.
    /// @dev Reverts if no value set.
    /// @return value The oracle's current value.
    function read() external view returns (uint256 value);
}

contract AdjudicationFrameworkFeeds is MinimalAdjudicationFramework {
    using EnumerableSet for EnumerableSet.AddressSet;

    // @dev Error thrown when non-allowlisted actor tries to call a function
    error OracleFrozen();

    /// @param _realityETH The reality.eth instance we adjudicate for
    /// @param _forkArbitrator The arbitrator contract that escalates to an L1 fork, used for our governance
    /// @param _initialArbitrators Arbitrator contracts we initially support
    /// @param _forkActivationDelay The delay before arbitration can be requested
    constructor(
        address _realityETH,
        address _forkArbitrator,
        address[] memory _initialArbitrators,
        uint256 _forkActivationDelay
    )
        MinimalAdjudicationFramework(
            _realityETH,
            _forkArbitrator,
            _initialArbitrators,
            true, // replace method can be used to switch out arbitrators
            _forkActivationDelay
        )
    {}

    function read() public view returns (uint256) {
        address oracle = getOracleContract();
        if (countArbitratorFreezePropositions[oracle] > 0) {
            revert OracleFrozen();
        }
        return IChronicle(oracle).read();
    }

    function getOracleContract() public view returns (address) {
        return _arbitrators.at(0);
    }
}
