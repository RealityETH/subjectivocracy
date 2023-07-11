pragma solidity ^0.8.17;

import "@RealityETH/zkevm-contracts/contracts/inheritedMainContracts/PolygonZkEVM.sol";
import "@RealityETH/zkevm-contracts/contracts/lib/TokenWrapped.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./interfaces/IForkableZkEVM.sol";
import "./mixin/ForkableUUPS.sol";

contract ForkableZkEVM is ForkableUUPS, IForkableZkEVM, PolygonZkEVM {
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
        IPolygonZkEVMBridge _bridgeAddress
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
            _bridgeAddress
        );
    }

    function createChildren(address implementation) external onlyForkManger returns (address, address) {
        return _createChildren(implementation);
    }

    modifier notAfterForking() {
        require(children[0] == address(0x0), "No sequencer changes after forking");
        _;
    } 

     function sequenceBatches(
        BatchData[] calldata batches,
        address l2Coinbase
    ) public override notAfterForking ifNotEmergencyState onlyTrustedSequencer{
        PolygonZkEVM.sequenceBatches(batches, l2Coinbase);
    }

    function verifyBatches(
        uint64 pendingStateNum,
        uint64 initNumBatch,
        uint64 finalNewBatch,
        bytes32 newLocalExitRoot,
        bytes32 newStateRoot,
        bytes calldata proof
    ) public override notAfterForking ifNotEmergencyState {
        PolygonZkEVM.verifyBatches(pendingStateNum, initNumBatch, finalNewBatch, newLocalExitRoot, newStateRoot, proof);
    }

    function verifyBatchesTrustedAggregator(
        uint64 pendingStateNum,
        uint64 initNumBatch,
        uint64 finalNewBatch,
        bytes32 newLocalExitRoot,
        bytes32 newStateRoot,
        bytes calldata proof
    ) public override notAfterForking onlyTrustedAggregator {
        PolygonZkEVM.verifyBatchesTrustedAggregator(pendingStateNum, initNumBatch, finalNewBatch, newLocalExitRoot, newStateRoot, proof);
    }
}
