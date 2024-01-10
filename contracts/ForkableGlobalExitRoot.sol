// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {PolygonZkEVMGlobalExitRoot} from "@RealityETH/zkevm-contracts/contracts/inheritedMainContracts/PolygonZkEVMGlobalExitRoot.sol";
import {ForkableStructure} from "./mixin/ForkableStructure.sol";
import {ForkableStructure} from "./mixin/ForkableStructure.sol";
import {IForkableGlobalExitRoot} from "./interfaces/IForkableGlobalExitRoot.sol";

contract ForkableGlobalExitRoot is
    IForkableGlobalExitRoot,
    ForkableStructure,
    PolygonZkEVMGlobalExitRoot
{
    /// @inheritdoc IForkableGlobalExitRoot
    function initialize(
        address _forkmanager,
        address _parentContract,
        address _rollupAddress,
        address _bridgeAddress,
        bytes32 _lastMainnetExitRoot,
        bytes32 _lastRollupExitRoot
    ) public initializer {
        ForkableStructure.initialize(_forkmanager, _parentContract);
        PolygonZkEVMGlobalExitRoot.initialize(
            _rollupAddress,
            _bridgeAddress,
            _lastMainnetExitRoot,
            _lastRollupExitRoot
        );
    }

    /// @dev Public interface to create children. This can only be done by the forkmanager
    /// @return The addresses of the two children
    function createChildren()
        external
        onlyForkManger
        returns (address, address)
    {
        return _createChildren();
    }
}
