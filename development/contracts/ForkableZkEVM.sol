pragma solidity ^0.8.17;

import "@RealityETH/zkevm-contracts/contracts/PolygonZkEVM.sol";
import "@RealityETH/zkevm-contracts/contracts/lib/TokenWrapped.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./mixin/ForkStructure.sol";
import "./interfaces/IForkableZkEVM.sol";

contract ForkableZkEVM is ForkStructure, IForkableZkEVM, PolygonZkEVM {
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
    ) external initializer {
        forkmanager = _forkmanager;
        parentContract = _parentContract;
        PolygonZkEVM.initialize(
            initializePackedParameters,
            genesisRoot,
            _trustedSequencerURL,
            _networkName,
            _version,
            _globalExitRootManager,
            _matic,
            _rollupVerifier,
            _bridgeAddress,
            _chainID,
            _forkID
        );
    }

    /**
     * @notice Allows the forkmanager to create the new children
     */
    function createChildren()
        external
        onlyForkManger
        returns (address, address)
    {
        // create emergency mode to stop all operations:
        _activateEmergencyState();
        address forkableZkEVM = ClonesUpgradeable.clone(address(this));
        children[0] = forkableZkEVM;
        forkableZkEVM = ClonesUpgradeable.clone(address(this));
        children[1] = forkableZkEVM;
        return (children[0], children[1]);
    }
}
