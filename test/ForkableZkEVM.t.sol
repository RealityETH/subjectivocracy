pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PolygonZkEVM} from "@RealityETH/zkevm-contracts/contracts/inheritedMainContracts/PolygonZkEVM.sol";
import {ForkableZkEVM} from "../contracts/ForkableZkEVM.sol";
import {IForkableStructure} from "../contracts/interfaces/IForkableStructure.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IPolygonZkEVMGlobalExitRoot} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMGlobalExitRoot.sol";
import {IVerifierRollup} from "@RealityETH/zkevm-contracts/contracts/interfaces/IVerifierRollup.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {IPolygonZkEVM} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import {Util} from "./utils/Util.sol";

contract ForkableZkEVMTest is Test {
    ForkableZkEVM public forkableZkEVM;

    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address public forkmanager = address(0x123);
    address public parentContract = address(0x456);
    address public updater =
        address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38);
    address public forkableZkEVMImplementation;

    IPolygonZkEVMGlobalExitRoot public _globalExitRootManager =
        IPolygonZkEVMGlobalExitRoot(0x1804c8ab1f12e6BBF3894d4083f33E07309d1f39);
    IERC20Upgradeable public _matic =
        IERC20Upgradeable(0x1804c8ab1f12E6bbF3894d4083F33e07309d1f40);
    IVerifierRollup public _rollupVerifier =
        IVerifierRollup(0x1804c8ab1f12E6BBf3894d4083F33E07309d1F41);
    IPolygonZkEVMBridge public _bridgeAddress =
        IPolygonZkEVMBridge(0x1804c8ab1F12E6BBF3894d4083f33e07309d1f42);

    bytes32 public genesisRoot = keccak256(abi.encodePacked("genesisRoot"));
    string public _trustedSequencerURL = "http://example.com";
    string public _networkName = "Test Network";
    string public _version = "1.0.0";
    uint64 public forkID = 3;
    uint64 public chainID = 4;
    uint32 public networkID = 10;
    address public admin = address(0x1234567890123456789012345678901234567890);
    uint64 public pendingStateTimeout = 123;
    uint64 public trustedAggregatorTimeout = 124235;
    address public trustedSequencer =
        address(0x1234567890123456789012345678901234567899);
    address public trustedAggregator =
        address(0x1234567890123456789012345678901234567898);
    IVerifierRollup public rollupVerifierMock =
        IVerifierRollup(0x1234567890123456789012345678901234567893);
    uint256 public arbitrationFee = 1020;

    function setUp() public {
        forkableZkEVMImplementation = address(new ForkableZkEVM());
        forkableZkEVM = ForkableZkEVM(
            address(
                new TransparentUpgradeableProxy(
                    forkableZkEVMImplementation,
                    admin,
                    ""
                )
            )
        );
        IPolygonZkEVM.InitializePackedParameters
            memory initializePackedParameters = IPolygonZkEVM
                .InitializePackedParameters({
                    admin: admin,
                    trustedSequencer: trustedSequencer,
                    pendingStateTimeout: pendingStateTimeout,
                    trustedAggregator: trustedAggregator,
                    trustedAggregatorTimeout: trustedAggregatorTimeout,
                    chainID: chainID,
                    forkID: forkID
                });
        forkableZkEVM.initialize(
            forkmanager,
            parentContract,
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

    function testInitialize() public {
        assertEq(forkableZkEVM.forkmanager(), forkmanager);
        assertEq(forkableZkEVM.parentContract(), parentContract);
    }

    function testCreateChildren() public {
        vm.expectRevert(IForkableStructure.OnlyForkManagerIsAllowed.selector);
        forkableZkEVM.createChildren();

        vm.prank(forkableZkEVM.forkmanager());
        (address child1, address child2) = forkableZkEVM.createChildren();

        // child1 and child2 addresses should not be zero address
        assertTrue(child1 != address(0));
        assertTrue(child2 != address(0));

        // the implementation address of children should match the expected ones
        assertEq(
            Util.bytesToAddress(vm.load(address(child1), _IMPLEMENTATION_SLOT)),
            forkableZkEVMImplementation
        );
        assertEq(
            Util.bytesToAddress(vm.load(address(child2), _IMPLEMENTATION_SLOT)),
            forkableZkEVMImplementation
        );
    }

    function testNoVerifyBatchesAfterForking() public {
        uint64 pendingStateNum = 10;
        uint64 initNumBatch = 12;
        uint64 finalNewBatch = 24;
        bytes32 newLocalExitRoot = keccak256(
            abi.encodePacked("newLocalExitRoot")
        );
        bytes32 newStateRoot = keccak256(abi.encodePacked("newStateRoot"));
        bytes32[24] memory proof;
        for (uint256 i = 0; i < 24; i++) {
            proof[i] = bytes32(abi.encodePacked("proof", i));
        }

        vm.prank(forkableZkEVM.forkmanager());
        forkableZkEVM.createChildren();

        vm.expectRevert(IForkableStructure.NoChangesAfterForking.selector);
        forkableZkEVM.verifyBatches(
            pendingStateNum,
            initNumBatch,
            finalNewBatch,
            newLocalExitRoot,
            newStateRoot,
            proof
        );
    }

    function testNoChangeOfConsolidationOfStateAfterForking() public {
        vm.prank(forkableZkEVM.forkmanager());
        forkableZkEVM.createChildren();

        vm.expectRevert(IForkableStructure.NoChangesAfterForking.selector);
        forkableZkEVM.consolidatePendingState(10);

        bytes32[24] memory proof;
        for (uint256 i = 0; i < 24; i++) {
            proof[i] = bytes32("0x"); // Whatever initialization value you want
        }

        vm.expectRevert(IForkableStructure.NoChangesAfterForking.selector);
        forkableZkEVM.overridePendingState(
            10,
            10,
            10,
            10,
            bytes32("0x"),
            bytes32("0x"),
            proof
        );

        vm.expectRevert(IForkableStructure.NoChangesAfterForking.selector);
        PolygonZkEVM.BatchData[] memory batches = new PolygonZkEVM.BatchData[](
            1
        );
        forkableZkEVM.sequenceBatches(batches, address(0));
    }

    function testModifierOfOverwrittenFunctionsStillActive() public {
        // We call the overridden function in the overriding function sequenceBatches
        // Here we test that PolygonZkEVM.sequenceBatches modifiers still are in place
        // and work as expected.
        PolygonZkEVM.BatchData[] memory batches = new PolygonZkEVM.BatchData[](
            1
        );
        batches[0] = PolygonZkEVM.BatchData({
            transactions: bytes("0x"),
            globalExitRoot: bytes32("0x"),
            timestamp: uint64(0),
            minForcedTimestamp: 0
        });
        address l2Coinbase = address(
            0x1234567890123456789012345678901234567899
        );
        bytes4 selector = bytes4(keccak256("OnlyTrustedSequencer()"));
        vm.expectRevert(selector);
        forkableZkEVM.sequenceBatches(batches, l2Coinbase);
    }
}
