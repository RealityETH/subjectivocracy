pragma solidity ^0.8.20;

/* solhint-disable not-rely-on-time */
/* solhint-disable reentrancy */
/* solhint-disable quotes */

import {Vm} from "forge-std/Vm.sol";

import {Test} from "forge-std/Test.sol";
import {Arbitrator} from "../contracts/lib/reality-eth/Arbitrator.sol";

import {VerifierRollupHelperMock} from "@RealityETH/zkevm-contracts/contracts/mocks/VerifierRollupHelperMock.sol";
import {IRealityETH} from "../contracts/lib/reality-eth/interfaces/IRealityETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ForkableRealityETH_ERC20} from "../contracts/ForkableRealityETH_ERC20.sol";
import {RealityETH_v3_0} from "../contracts/lib/reality-eth/RealityETH-3.0.sol";
import {AdjudicationFramework} from "../contracts/AdjudicationFramework/AdjudicationFrameworkForRequestsWithChallengeManagement.sol";

import {IForkableStructure} from "../contracts/interfaces/IForkableStructure.sol";
import {L2ForkArbitrator} from "../contracts/L2ForkArbitrator.sol";
import {L1GlobalChainInfoPublisher} from "../contracts/L1GlobalChainInfoPublisher.sol";
import {L1GlobalForkRequester} from "../contracts/L1GlobalForkRequester.sol";
import {L2ChainInfo} from "../contracts/L2ChainInfo.sol";

import {MockPolygonZkEVMBridge} from "./testcontract/MockPolygonZkEVMBridge.sol";

pragma solidity ^0.8.20;

/* solhint-disable not-rely-on-time */

import {Test} from "forge-std/Test.sol";
import {ForkingManager} from "../contracts/ForkingManager.sol";
import {ForkableBridge} from "../contracts/ForkableBridge.sol";
import {ForkableZkEVM} from "../contracts/ForkableZkEVM.sol";
import {ForkonomicToken} from "../contracts/ForkonomicToken.sol";
import {ForkableGlobalExitRoot} from "../contracts/ForkableGlobalExitRoot.sol";
import {IBasePolygonZkEVMGlobalExitRoot} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMGlobalExitRoot.sol";
import {IForkingManager} from "../contracts/interfaces/IForkingManager.sol";
import {IVerifierRollup} from "@RealityETH/zkevm-contracts/contracts/interfaces/IVerifierRollup.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {PolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/inheritedMainContracts/PolygonZkEVMBridge.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import {IPolygonZkEVM} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ChainIdManager} from "../contracts/ChainIdManager.sol";
import {ForkableZkEVM} from "../contracts/ForkableZkEVM.sol";

contract L1GlobalChainInfoPublisherTest is Test {
    ForkableBridge public bridge;
    ForkonomicToken public forkonomicToken;
    ForkingManager public forkmanager;
    ForkableZkEVM public zkevm;
    ForkableGlobalExitRoot public globalExitRoot;

    ForkableBridge public l2Bridge;

    address public bridgeImplementation;
    address public forkmanagerImplementation;
    address public zkevmImplementation;
    address public forkonomicTokenImplementation;
    address public globalExitRootImplementation;
    address public chainIdManagerAddress;
    uint256 public forkPreparationTime = 1000;
    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    bytes32 public genesisRoot =
        bytes32(
            0x827a9240c96ccb855e4943cc9bc49a50b1e91ba087007441a1ae5f9df8d1c57c
        );
    uint64 public forkID = 3;
    uint64 public newForkID = 4;
    uint32 public networkID = 10;
    uint64 public pendingStateTimeout = 123;
    uint64 public trustedAggregatorTimeout = 124235;
    address public hardAssetManger =
        address(0x1234567890123456789012345678901234567891);
    address public trustedSequencer =
        address(0x1234567890123456789012345678901234567899);
    address public trustedAggregator =
        address(0x1234567890123456789012345678901234567898);
    IVerifierRollup public rollupVerifierMock =
        IVerifierRollup(0x1234567890123456789012345678901234567893);
    uint256 public arbitrationFee = 1020;
    bytes32[32] public depositTree;
    address public admin = address(0xad);
    uint64 public initialChainId = 1;
    uint64 public firstChainId = initialChainId + 1;
    uint64 public secondChainId = initialChainId + 2;

    // Setup new implementations for the fork
    address public newBridgeImplementation = address(new ForkableBridge());
    address public newForkmanagerImplementation = address(new ForkingManager());
    address public newZkevmImplementation = address(new ForkableZkEVM());

    address public newVerifierImplementation =
        address(new VerifierRollupHelperMock());
    address public newGlobalExitRootImplementation =
        address(new ForkableGlobalExitRoot());
    address public newForkonomicTokenImplementation =
        address(new ForkonomicToken());
    address public disputeContract =
        address(0x1234567890123456789012345678901234567894);
    bytes32 public disputeContent = "0x34567890129";
    bool public isL1 = true;

    L1GlobalChainInfoPublisher public l1GlobalChainInfoPublisher =
        new L1GlobalChainInfoPublisher();
    L2ChainInfo public l2ChainInfo =
        new L2ChainInfo(address(l2Bridge), address(l1GlobalChainInfoPublisher));

    ForkingManager.DisputeData public disputeData =
        IForkingManager.DisputeData({
            disputeContract: disputeContract,
            disputeContent: disputeContent,
            isL1: isL1
        });

    event Transfer(address indexed from, address indexed to, uint256 tokenId);

    function bytesToAddress(bytes32 b) public pure returns (address) {
        return address(uint160(uint256(b)));
    }

    function setUp() public {
        bridgeImplementation = address(new ForkableBridge());
        bridge = ForkableBridge(
            address(
                new TransparentUpgradeableProxy(bridgeImplementation, admin, "")
            )
        );

        // Bridge on l2, should have different chain ID etc
        l2Bridge = ForkableBridge(
            address(
                new TransparentUpgradeableProxy(bridgeImplementation, admin, "")
            )
        );

        forkmanagerImplementation = address(new ForkingManager());
        forkmanager = ForkingManager(
            address(
                new TransparentUpgradeableProxy(
                    forkmanagerImplementation,
                    admin,
                    ""
                )
            )
        );
        zkevmImplementation = address(new ForkableZkEVM());
        zkevm = ForkableZkEVM(
            address(
                new TransparentUpgradeableProxy(zkevmImplementation, admin, "")
            )
        );
        forkonomicTokenImplementation = address(new ForkonomicToken());
        forkonomicToken = ForkonomicToken(
            address(
                new TransparentUpgradeableProxy(
                    forkonomicTokenImplementation,
                    admin,
                    ""
                )
            )
        );
        globalExitRootImplementation = address(new ForkableGlobalExitRoot());
        globalExitRoot = ForkableGlobalExitRoot(
            address(
                new TransparentUpgradeableProxy(
                    globalExitRootImplementation,
                    admin,
                    ""
                )
            )
        );
        ChainIdManager chainIdManager = new ChainIdManager(initialChainId);
        chainIdManagerAddress = address(chainIdManager);
        globalExitRoot.initialize(
            address(forkmanager),
            address(0x0),
            address(zkevm),
            address(bridge),
            bytes32(0),
            bytes32(0)
        );
        bridge.initialize(
            address(forkmanager),
            address(0x0),
            networkID,
            globalExitRoot,
            address(zkevm),
            address(forkonomicToken),
            false,
            hardAssetManger,
            0,
            depositTree
        );

        IPolygonZkEVM.InitializePackedParameters
            memory initializePackedParameters = IPolygonZkEVM
                .InitializePackedParameters({
                    admin: admin,
                    trustedSequencer: trustedSequencer,
                    pendingStateTimeout: pendingStateTimeout,
                    trustedAggregator: trustedAggregator,
                    trustedAggregatorTimeout: trustedAggregatorTimeout,
                    chainID: chainIdManager.getNextUsableChainId(),
                    forkID: forkID
                });
        zkevm.initialize(
            address(forkmanager),
            address(0x0),
            initializePackedParameters,
            genesisRoot,
            "trustedSequencerURL",
            "test network",
            "0.0.1",
            globalExitRoot,
            IERC20Upgradeable(address(forkonomicToken)),
            rollupVerifierMock,
            IPolygonZkEVMBridge(address(bridge))
        );
        forkmanager.initialize(
            address(zkevm),
            address(bridge),
            address(forkonomicToken),
            address(0x0),
            address(globalExitRoot),
            arbitrationFee,
            chainIdManagerAddress,
            forkPreparationTime
        );
        forkonomicToken.initialize(
            address(forkmanager),
            address(0x0),
            address(this),
            "Fork",
            "FORK"
        );
    }

    function testChainInfoPublishedBeforeFork() public {
        // vm.recordLogs();
        l1GlobalChainInfoPublisher.updateL2ChainInfo(
            address(bridge),
            address(l2ChainInfo),
            address(0),
            10
        );
        // Vm.Log[] memory entries = vm.getRecordedLogs();
        // TODO: Check the logs
    }

    function testChainInfoPublishedBeforeForkBreaksWithBrokenBridge() public {
        address garbageAddress = address(0xabcd01);
        vm.expectRevert();
        l1GlobalChainInfoPublisher.updateL2ChainInfo(
            garbageAddress,
            address(l2ChainInfo),
            address(0),
            10
        );
    }

    function testChainInfoPublishedBeforeForkRevertsWithBrokenAncestor()
        public
    {
        address garbageAddress = address(0xabcd01);
        vm.expectRevert(L1GlobalChainInfoPublisher.AncestorNotFound.selector);
        l1GlobalChainInfoPublisher.updateL2ChainInfo(
            address(bridge),
            address(l2ChainInfo),
            garbageAddress,
            10
        );
    }

    function testChainInfoPublishedAfterForks() public {
        // Mint and approve the arbitration fee for the test contract
        // We'll do several for repeated forks
        forkonomicToken.approve(address(forkmanager), arbitrationFee * 3);
        vm.prank(address(this));
        forkonomicToken.mint(address(this), arbitrationFee * 3);

        // Call the initiateFork function to create a new fork
        forkmanager.initiateFork(disputeData);
        skip(forkmanager.forkPreparationTime() + 1);
        forkmanager.executeFork();

        // The current bridge should no longer work
        vm.expectRevert(IForkableStructure.NoChangesAfterForking.selector);
        l1GlobalChainInfoPublisher.updateL2ChainInfo(
            address(bridge),
            address(l2ChainInfo),
            address(0),
            uint256(10)
        );

        (address forkmanager1Addrg, address forkmanager2Addr) = forkmanager
            .getChildren();
        address bridge1 = IForkingManager(forkmanager1Addrg).bridge();
        address bridge2 = IForkingManager(forkmanager2Addr).bridge();

        // The new bridges should work though
        l1GlobalChainInfoPublisher.updateL2ChainInfo(
            bridge1,
            address(l2ChainInfo),
            address(0),
            uint256(10)
        );
        l1GlobalChainInfoPublisher.updateL2ChainInfo(
            bridge2,
            address(l2ChainInfo),
            address(0),
            uint256(10)
        );

        l1GlobalChainInfoPublisher.updateL2ChainInfo(
            bridge1,
            address(l2ChainInfo),
            address(forkmanager),
            uint256(10)
        );
        l1GlobalChainInfoPublisher.updateL2ChainInfo(
            bridge2,
            address(l2ChainInfo),
            address(forkmanager),
            uint256(10)
        );

        ForkingManager forkmanager2 = ForkingManager(forkmanager2Addr);
        ForkonomicToken forkonomicToken2 = ForkonomicToken(
            forkmanager2.forkonomicToken()
        );

        // Next we'll fork with a dispute
        ForkingManager.DisputeData memory disputeData2 = IForkingManager
            .DisputeData({
                disputeContract: address(0xabab),
                disputeContent: bytes32("0xbaba"),
                isL1: true
            });

        forkonomicToken.splitTokensIntoChildTokens(arbitrationFee);
        forkonomicToken2.approve(address(forkmanager2), arbitrationFee);
        vm.prank(address(this));

        // Call the initiateFork function to create a new fork
        forkmanager2.initiateFork(disputeData2);
        skip(forkmanager.forkPreparationTime() + 1);
        forkmanager2.executeFork();

        vm.expectRevert(IForkableStructure.NoChangesAfterForking.selector);
        l1GlobalChainInfoPublisher.updateL2ChainInfo(
            bridge2,
            address(l2ChainInfo),
            address(forkmanager),
            uint256(10)
        );

        (, address forkmanager22Addr) = forkmanager2.getChildren();
        // address bridge21 = IForkingManager(forkmanager21Addrg).bridge();
        address bridge22 = IForkingManager(forkmanager22Addr).bridge();

        l1GlobalChainInfoPublisher.updateL2ChainInfo(
            bridge22,
            address(l2ChainInfo),
            address(forkmanager),
            uint256(10)
        );

        vm.expectRevert(L1GlobalChainInfoPublisher.AncestorNotFound.selector);
        l1GlobalChainInfoPublisher.updateL2ChainInfo(
            bridge22,
            address(l2ChainInfo),
            address(forkmanager),
            uint256(0)
        );
        vm.expectRevert(L1GlobalChainInfoPublisher.AncestorNotFound.selector);
        l1GlobalChainInfoPublisher.updateL2ChainInfo(
            bridge22,
            address(l2ChainInfo),
            address(forkmanager),
            uint256(1)
        );

        l1GlobalChainInfoPublisher.updateL2ChainInfo(
            bridge22,
            address(l2ChainInfo),
            address(forkmanager),
            uint256(2)
        );
    }
}
