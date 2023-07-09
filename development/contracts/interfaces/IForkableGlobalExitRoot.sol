pragma solidity ^0.8.17;

import "./IForkableStructure.sol";
import "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMGlobalExitRoot.sol";

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

    function createChildren(
        address implementation
    ) external returns (address, address);
}
