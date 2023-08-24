pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {ForkingManager} from "../development/contracts/ForkingManager.sol";
import {ForkableBridge} from "../development/contracts/ForkableBridge.sol";
import {ForkableZkEVM} from "../development/contracts/ForkableZkEVM.sol";
import {ForkonomicToken} from "../development/contracts/ForkonomicToken.sol";
import {ForkableGlobalExitRoot} from "../development/contracts/ForkableGlobalExitRoot.sol";
import {IBasePolygonZkEVMGlobalExitRoot} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMGlobalExitRoot.sol";
import {IForkingManager} from "../development/contracts/interfaces/IForkingManager.sol";
import {IVerifierRollup} from "@RealityETH/zkevm-contracts/contracts/interfaces/IVerifierRollup.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import {IPolygonZkEVM} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract ForkingManagerTest is Test {
    ForkableBridge public bridge;
    ForkonomicToken public forkonomicToken;
    ForkingManager public forkmanager;
    ForkableZkEVM public zkevm;
    ForkableGlobalExitRoot public globalExitRoot;

    address public bridgeImplementation;
    address public forkmanagerImplementation;
    address public zkevmImplementation;
    address public forkonomicTokenImplementation;
    address public globalExitRootImplementation;
    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    IBasePolygonZkEVMGlobalExitRoot public globalExitMock =
        IBasePolygonZkEVMGlobalExitRoot(
            0x1234567890123456789012345678901234567892
        );
    bytes32 public genesisRoot =
        bytes32(
            0x827a9240c96ccb855e4943cc9bc49a50b1e91ba087007441a1ae5f9df8d1c57c
        );
    uint64 public forkID = 3;
    uint64 public chainID = 4;
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

    // Setup new implementations for the fork
    address public newBridgeImplementation = address(new ForkableBridge());
    address public newForkmanagerImplementation = address(new ForkingManager());
    address public newZkevmImplementation = address(new ForkableZkEVM());
    address public newVerifierImplementation =
        address(0x1234567890123456789012345678901234567894);
    address public newGlobalExitRootImplementation =
        address(new ForkableGlobalExitRoot());
    address public newForkonomicTokenImplementation =
        address(new ForkonomicToken());
    address public disputeContract =
        address(0x1234567890123456789012345678901234567894);
    bytes public disputeCall = "0x34567890129";

    ForkingManager.DisputeData public disputeData =
        IForkingManager.DisputeData({
            disputeContract: disputeContract,
            disputeCall: disputeCall
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
        globalExitRoot.initialize(
            address(forkmanager),
            address(0x0),
            address(zkevm),
            address(bridge)
        );
        bridge.initialize(
            address(forkmanager),
            address(0x0),
            networkID,
            globalExitMock,
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
                    chainID: chainID,
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
        IForkingManager.ForkProposal[] memory proposals;
        forkmanager.initialize(
            address(zkevm),
            address(bridge),
            address(forkonomicToken),
            address(0x0),
            address(globalExitRoot),
            arbitrationFee,
            proposals
        );
        forkonomicToken.initialize(
            address(forkmanager),
            address(0x0),
            address(this),
            "Fork",
            "FORK"
        );
    }

    function testInitiateForkChargesFees() public {
        // Call the initiateFork function to create a new fork
        vm.expectRevert(bytes("ERC20: insufficient allowance"));
        forkmanager.initiateFork(
            IForkingManager.DisputeData({
                disputeContract: disputeContract,
                disputeCall: disputeCall
            }),
            IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation
            }),
            0
        );

        // Mint and approve the arbitration fee for the test contract
        forkonomicToken.approve(address(forkmanager), arbitrationFee);
        vm.prank(address(this));
        forkonomicToken.mint(address(this), arbitrationFee);

        vm.expectEmit(true, true, true, true, address(forkonomicToken));
        emit Transfer(
            address(this),
            address(forkmanager),
            uint256(arbitrationFee)
        );

        forkmanager.initiateFork(
            IForkingManager.DisputeData({
                disputeContract: disputeContract,
                disputeCall: disputeCall
            }),
            IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation
            }),
            0
        );
    }

    function testInitiateForkAndExecuteSetsCorrectImplementations() public {
        // Mint and approve the arbitration fee for the test contract
        forkonomicToken.approve(address(forkmanager), arbitrationFee);
        vm.prank(address(this));
        forkonomicToken.mint(address(this), arbitrationFee);

        // Call the initiateFork function to create a new fork
        uint256 id = forkmanager.initiateFork(
            disputeData,
            IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation
            }),
            0
        );
        forkmanager.executeFork(id);

        // Fetch the children from the ForkingManager
        (address childForkmanager1, address childForkmanager2) = forkmanager
            .getChildren();

        // Assert that the fork managers implementation match the ones we provided
        assertEq(
            bytesToAddress(
                vm.load(address(childForkmanager1), _IMPLEMENTATION_SLOT)
            ),
            forkmanagerImplementation
        );
        assertEq(
            bytesToAddress(
                vm.load(address(childForkmanager2), _IMPLEMENTATION_SLOT)
            ),
            newForkmanagerImplementation
        );

        {
            // Fetch the children from the ForkableBridge contract
            (address childBridge1, address childBridge2) = bridge.getChildren();

            // Assert that the bridges match the ones we provided
            assertEq(
                bytesToAddress(
                    vm.load(address(childBridge1), _IMPLEMENTATION_SLOT)
                ),
                bridgeImplementation
            );
            assertEq(
                bytesToAddress(
                    vm.load(address(childBridge2), _IMPLEMENTATION_SLOT)
                ),
                newBridgeImplementation
            );
        }
        {
            // Fetch the children from the ForkableZkEVM contract
            (address childZkevm1, address childZkevm2) = zkevm.getChildren();

            // Assert that the ZkEVM contracts match the ones we provided
            assertEq(
                bytesToAddress(
                    vm.load(address(childZkevm1), _IMPLEMENTATION_SLOT)
                ),
                zkevmImplementation
            );
            assertEq(
                bytesToAddress(
                    vm.load(address(childZkevm2), _IMPLEMENTATION_SLOT)
                ),
                newZkevmImplementation
            );
        }
        {
            // Fetch the children from the ForkonomicToken contract
            (
                address childForkonomicToken1,
                address childForkonomicToken2
            ) = forkonomicToken.getChildren();

            // Assert that the forkonomic tokens match the ones we provided
            assertEq(
                bytesToAddress(
                    vm.load(
                        address(childForkonomicToken1),
                        _IMPLEMENTATION_SLOT
                    )
                ),
                forkonomicTokenImplementation
            );
            assertEq(
                bytesToAddress(
                    vm.load(
                        address(childForkonomicToken2),
                        _IMPLEMENTATION_SLOT
                    )
                ),
                newForkonomicTokenImplementation
            );
        }
        {
            // Fetch the children from the ForkonomicToken contract
            (
                address childGlobalExitRoot1,
                address childGlobalExitRoot2
            ) = globalExitRoot.getChildren();

            // Assert that the forkonomic tokens match the ones we provided
            assertEq(
                bytesToAddress(
                    vm.load(address(childGlobalExitRoot1), _IMPLEMENTATION_SLOT)
                ),
                globalExitRootImplementation
            );
            assertEq(
                bytesToAddress(
                    vm.load(address(childGlobalExitRoot2), _IMPLEMENTATION_SLOT)
                ),
                newGlobalExitRootImplementation
            );

            assertEq(
                ForkableGlobalExitRoot(childGlobalExitRoot1).forkmanager(),
                childForkmanager1
            );
        }
    }

    function testInitiateForkSetsDispuateDataAndExecutionTime() public {
        // Mint and approve the arbitration fee for the test contract
        forkonomicToken.approve(address(forkmanager), arbitrationFee);
        vm.prank(address(this));
        forkonomicToken.mint(address(this), arbitrationFee);

        // Call the initiateFork function to create a new fork
        uint256 testTimestamp = 123454234;
        vm.warp(testTimestamp);
        uint256 id = forkmanager.initiateFork(
            disputeData,
            IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation
            }),
            0
        );
        forkmanager.executeFork(id);

        (
            ForkingManager.DisputeData memory receivedDisputeData,
            ,
            uint256 receivedExecutionTime
        ) = ForkingManager(forkmanager).forkProposals(0);

        // Assert the dispute contract and call stored in the ForkingManager match the ones we provided
        assertEq(receivedDisputeData.disputeContract, disputeContract);
        assertEq(receivedDisputeData.disputeCall, disputeCall);
        assertEq(receivedExecutionTime, testTimestamp);
    }

    function testExecuteForkRespectsTime() public {
        // reverts on empty proposal list
        vm.expectRevert("ForkingManager: fork not ready");
        forkmanager.executeFork(0);

        // Mint and approve the arbitration fee for the test contract
        forkonomicToken.approve(address(forkmanager), arbitrationFee);
        vm.prank(address(this));
        forkonomicToken.mint(address(this), arbitrationFee);

        // Call the initiateFork function to create a new fork
        uint256 duration = 100;
        uint256 testTimestamp = 123454234;
        vm.warp(testTimestamp);
        uint256 id = forkmanager.initiateFork(
            disputeData,
            IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation
            }),
            duration
        );

        vm.expectRevert("ForkingManager: fork not ready");
        forkmanager.executeFork(id);
        vm.warp(testTimestamp + duration);
        forkmanager.executeFork(id);
    }

    function testExecuteForkCanOnlyExecutedOnce() public {
        // Mint and approve the arbitration fee for the test contract
        forkonomicToken.approve(address(forkmanager), arbitrationFee);
        vm.prank(address(this));
        forkonomicToken.mint(address(this), arbitrationFee);

        // Call the initiateFork function to create a new fork
        uint256 testTimestamp = 123454234;
        vm.warp(testTimestamp);
        uint256 id = forkmanager.initiateFork(
            disputeData,
            IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation
            }),
            0
        );

        forkmanager.executeFork(id);
        vm.expectRevert("No changes after forking");
        forkmanager.executeFork(id);
    }

    function testExecuteForkCopiesForkProposals() public {
        // Mint and approve the arbitration fee for the test contract
        forkonomicToken.approve(address(forkmanager), 3 * arbitrationFee);
        vm.prank(address(this));
        forkonomicToken.mint(address(this), 3 * arbitrationFee);

        // Call the initiateFork function to create a new fork
        disputeData.disputeCall = "0x1";
        forkmanager.initiateFork(
            disputeData,
            IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation
            }),
            0
        );
        disputeData.disputeCall = "0x2";
        uint256 id = forkmanager.initiateFork(
            disputeData,
            IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation
            }),
            0
        );
        disputeData.disputeCall = "0x3";
        forkmanager.initiateFork(
            disputeData,
            IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation
            }),
            0
        );

        forkmanager.executeFork(id);
        (address forkManagerChild1, address forkManagerChild2) = forkmanager
            .getChildren();
        (IForkingManager.DisputeData memory data1, , ) = ForkingManager(
            forkManagerChild1
        ).forkProposals(0);
        assertEq(data1.disputeCall, "0x1");
        (IForkingManager.DisputeData memory data2, , ) = ForkingManager(
            forkManagerChild2
        ).forkProposals(0);
        assertEq(data2.disputeCall, "0x1");
        (IForkingManager.DisputeData memory data3, , ) = ForkingManager(
            forkManagerChild1
        ).forkProposals(1);
        assertEq(data3.disputeCall, "0x3");
        (IForkingManager.DisputeData memory data4, , ) = ForkingManager(
            forkManagerChild2
        ).forkProposals(1);
        assertEq(data4.disputeCall, "0x3");
    }
}
