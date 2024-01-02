// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {IForkableStructure} from "./IForkableStructure.sol";
import {IPolygonZkEVMGlobalExitRoot} from "@josojo/zkevm-contracts/contracts/interfaces/IPolygonZkEVMGlobalExitRoot.sol";

interface IForkableGlobalExitRoot is
    IForkableStructure,
    IPolygonZkEVMGlobalExitRoot
{
    /// @dev Initializting function
    /// @param _forkmanager The address of the forkmanager
    /// @param _parentContract The address of the parent contract
    /// @param _rollupAddress The address of the rollup contract
    /// @param _bridgeAddress The address of the bridge contract
    /// @param _lastMainnetExitRoot The last exit root on mainnet
    /// @param _lastRollupExitRoot The last exit root on rollup
    function initialize(
        address _forkmanager,
        address _parentContract,
        address _rollupAddress,
        address _bridgeAddress,
        bytes32 _lastMainnetExitRoot,
        bytes32 _lastRollupExitRoot
    ) external;

    /**
     * @dev Function to create the children contracts
     */
    function createChildren() external returns (address, address);
}
