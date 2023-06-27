pragma solidity ^0.8.17;

import "./IForkableStructure.sol";
import "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";
import "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMGlobalExitRoot.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@RealityETH/zkevm-contracts/contracts/interfaces/IVerifierRollup.sol";
import "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";

interface IForkableZkEVM is IForkableStructure, IPolygonZkEVM {
    function initialize(
        address _forkmanager,
        address _parentContract,
        InitializePackedParameters calldata initializePackedParameters,
        bytes32 genesisRoot,
        string memory _trustedSequencerURL,
        string memory _networkName,
        string calldata _version,
        IPolygonZkEVMGlobalExitRoot _globalExitRootManager,
        IERC20Upgradeable _matic,
        IVerifierRollup _rollupVerifier,
        IPolygonZkEVMBridge _bridgeAddress,
        uint64 _chainID,
        uint64 _forkID
    ) external;

    function createChildren(
        address implementation
    ) external returns (address, address);
}
