// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;

import {ForkableGlobalExitRoot} from "../../contracts/ForkableGlobalExitRoot.sol";

/**
 * Contract responsible for managing the exit roots across multiple networks

 */
contract ForkableExitMock is ForkableGlobalExitRoot {
    /**
     * @notice Set last global exit root
     * @param timestamp timestamp
     */
    function setLastGlobalExitRoot(uint256 timestamp) public {
        globalExitRootMap[getLastGlobalExitRoot()] = timestamp;
    }

    /**
     * @notice Set last global exit root
     * @param timestamp timestamp
     */
    function setGlobalExitRoot(
        bytes32 globalExitRoot,
        uint256 timestamp
    ) public {
        globalExitRootMap[globalExitRoot] = timestamp;
    }
}
