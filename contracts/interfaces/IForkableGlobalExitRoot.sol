// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {IForkableStructure} from "./IForkableStructure.sol";
import {IPolygonZkEVMGlobalExitRoot} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMGlobalExitRoot.sol";

interface IForkableGlobalExitRoot is
    IForkableStructure,
    IPolygonZkEVMGlobalExitRoot
{
    function initialize(
        address _forkmanager,
        address _parentContract,
        address _rollupAddress,
        address _bridgeAddress
    ) external;

    function createChild2(address implementation) external returns (address);

    function createChild1() external returns (address);

    function createChildren(
        address implementation
    ) external returns (address, address);
}
