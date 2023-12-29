pragma solidity ^0.8.20;

/* solhint-disable not-rely-on-time */

import {Test} from "forge-std/Test.sol";
import {VerifierRollupHelperMock} from "@RealityETH/zkevm-contracts/contracts/mocks/VerifierRollupHelperMock.sol";
import {ForkingManager} from "../contracts/ForkingManager.sol";
import {ForkableBridge} from "../contracts/ForkableBridge.sol";
import {ForkableZkEVM} from "../contracts/ForkableZkEVM.sol";
import {ForkonomicToken} from "../contracts/ForkonomicToken.sol";
import {ForkableGlobalExitRoot} from "../contracts/ForkableGlobalExitRoot.sol";
import {IPolygonZkEVMGlobalExitRoot} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMGlobalExitRoot.sol";
import {IForkingManager} from "../contracts/interfaces/IForkingManager.sol";
import {IVerifierRollup} from "@RealityETH/zkevm-contracts/contracts/interfaces/IVerifierRollup.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {PolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/inheritedMainContracts/PolygonZkEVMBridge.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import {IPolygonZkEVM} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ChainIdManager} from "../contracts/ChainIdManager.sol";
import {ForkableZkEVM} from "../contracts/ForkableZkEVM.sol";

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
    address public chainIdManagerAddress;
    uint256 public forkPreparationTime = 1000;
    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    IPolygonZkEVMGlobalExitRoot public globalExitMock =
        IPolygonZkEVMGlobalExitRoot(
            0x1234567890123456789012345678901234567892
        );
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

    function testForkingStatusFunctions() public {
        assertFalse(forkmanager.isForkingInitiated());
        assertFalse(forkmanager.isForkingExecuted());
        assertTrue(forkmanager.canFork());

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
                disputeContent: disputeContent,
                isL1: isL1
            }),
            IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation,
                forkID: newForkID
            })
        );

        assertTrue(forkmanager.isForkingInitiated());
        assertFalse(forkmanager.isForkingExecuted());
        assertFalse(forkmanager.canFork());

        vm.warp(block.timestamp + forkmanager.forkPreparationTime() + 1);
        forkmanager.executeFork1();
        forkmanager.executeFork2();

        assertTrue(forkmanager.isForkingInitiated());
        assertTrue(forkmanager.isForkingExecuted());
        assertFalse(forkmanager.canFork());
    }

    function testVerifyNewImplementationsRejectsNonContractBridgeImplementation()
        public
    {
        forkonomicToken.approve(address(forkmanager), arbitrationFee);
        vm.prank(address(this));
        forkonomicToken.mint(address(this), arbitrationFee);
        IForkingManager.NewImplementations
            memory implementations = IForkingManager.NewImplementations({
                bridgeImplementation: address(0x1), // non contract
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation,
                forkID: newForkID
            });

        vm.expectRevert("bridge not contract");
        forkmanager.initiateFork(disputeData, implementations);
    }

    function testVerifyNewImplementationsRejectsNonContractZkEVMImplementation()
        public
    {
        forkonomicToken.approve(address(forkmanager), arbitrationFee);
        vm.prank(address(this));
        forkonomicToken.mint(address(this), arbitrationFee);
        IForkingManager.NewImplementations
            memory implementations = IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation, // non contract
                zkEVMImplementation: address(0x234),
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation,
                forkID: newForkID
            });

        vm.expectRevert("zkEVM not contract");
        forkmanager.initiateFork(disputeData, implementations);
    }

    function testInitiateForkChargesFees() public {
        // Call the initiateFork function to create a new fork
        vm.expectRevert(bytes("ERC20: insufficient allowance"));
        forkmanager.initiateFork(
            IForkingManager.DisputeData({
                disputeContract: disputeContract,
                disputeContent: disputeContent,
                isL1: isL1
            }),
            IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation,
                forkID: newForkID
            })
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
                disputeContent: disputeContent,
                isL1: isL1
            }),
            IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation,
                forkID: newForkID
            })
        );
    }

    function testInitiateForkAndExecuteSetsCorrectImplementations() public {
        // Mint and approve the arbitration fee for the test contract
        forkonomicToken.approve(address(forkmanager), arbitrationFee);
        vm.prank(address(this));
        forkonomicToken.mint(address(this), arbitrationFee);

        // Call the initiateFork function to create a new fork
        forkmanager.initiateFork(
            disputeData,
            IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation,
                forkID: newForkID
            })
        );
        vm.warp(block.timestamp + forkmanager.forkPreparationTime() + 1);
        forkmanager.executeFork1();
        forkmanager.executeFork2();

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
            (address childBridge1, address childBridge2) = bridge.getChildren();
            assertEq(
                ForkableBridge(childBridge1).polygonZkEVMaddress(),
                childZkevm1
            );
            assertEq(
                ForkableBridge(childBridge2).polygonZkEVMaddress(),
                childZkevm2
            );
            assertEq(ForkableZkEVM(childZkevm1).chainID(), firstChainId);
            assertEq(ForkableZkEVM(childZkevm2).chainID(), secondChainId);
            assertEq(
                ForkableZkEVM(childZkevm1).forkID(),
                ForkableZkEVM(zkevm).forkID()
            );
            assertEq(ForkableZkEVM(childZkevm2).forkID(), newForkID);
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
        {
            assertEq(
                chainIdManagerAddress,
                ForkingManager(childForkmanager1).chainIdManager()
            );
            assertEq(
                chainIdManagerAddress,
                ForkingManager(childForkmanager2).chainIdManager()
            );
        }
    }

    function testInitiateForkAndExecuteWorksWithoutChangingImplementations()
        public
    {
        // Mint and approve the arbitration fee for the test contract
        forkonomicToken.approve(address(forkmanager), arbitrationFee);
        vm.prank(address(this));
        forkonomicToken.mint(address(this), arbitrationFee);

        IForkingManager.NewImplementations memory noNewImplementations;
        // Call the initiateFork function to create a new fork
        forkmanager.initiateFork(disputeData, noNewImplementations);
        vm.warp(block.timestamp + forkmanager.forkPreparationTime() + 1);
        forkmanager.executeFork1();
        forkmanager.executeFork2();

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
            forkmanagerImplementation
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
                bridgeImplementation
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
                zkevmImplementation
            );
            (address childBridge1, address childBridge2) = bridge.getChildren();
            assertEq(
                ForkableBridge(childBridge1).polygonZkEVMaddress(),
                childZkevm1
            );
            assertEq(
                ForkableBridge(childBridge2).polygonZkEVMaddress(),
                childZkevm2
            );
            assertEq(ForkableZkEVM(childZkevm1).chainID(), firstChainId);
            assertEq(ForkableZkEVM(childZkevm2).chainID(), secondChainId);
            assertEq(
                ForkableZkEVM(childZkevm1).forkID(),
                ForkableZkEVM(zkevm).forkID()
            );
            assertEq(
                ForkableZkEVM(childZkevm2).forkID(),
                ForkableZkEVM(zkevm).forkID()
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
                forkonomicTokenImplementation
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
                globalExitRootImplementation
            );

            assertEq(
                ForkableGlobalExitRoot(childGlobalExitRoot1).forkmanager(),
                childForkmanager1
            );
        }
        {
            assertEq(
                chainIdManagerAddress,
                ForkingManager(childForkmanager1).chainIdManager()
            );
            assertEq(
                chainIdManagerAddress,
                ForkingManager(childForkmanager2).chainIdManager()
            );
        }
    }

    function testInitiateForkSetsDisputeDataAndExecutionTimeAndReservesChainIds()
        public
    {
        // Mint and approve the arbitration fee for the test contract
        forkonomicToken.approve(address(forkmanager), arbitrationFee);
        vm.prank(address(this));
        forkonomicToken.mint(address(this), arbitrationFee);

        // Call the initiateFork function to create a new fork
        uint256 testTimestamp = 123454234;
        vm.warp(testTimestamp);
        forkmanager.initiateFork(
            disputeData,
            IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation,
                forkID: newForkID
            })
        );
        skip(forkmanager.forkPreparationTime() + 1);
        forkmanager.executeFork1();
        forkmanager.executeFork2();

        (
            bool receivedIsL1,
            address receivedDisputeContract,
            bytes32 receivedDisputeContent
        ) = ForkingManager(forkmanager).disputeData();
        uint256 receivedExecutionTime = ForkingManager(forkmanager)
            .executionTimeForProposal();

        // Assert the dispute contract and call stored in the ForkingManager match the ones we provided
        assertEq(receivedDisputeContract, disputeContract);
        assertEq(receivedDisputeContent, disputeContent);
        assertEq(receivedIsL1, isL1);
        assertEq(
            receivedExecutionTime,
            testTimestamp + forkmanager.forkPreparationTime()
        );

        uint64 reservedChainIdForFork1 = ForkingManager(forkmanager)
            .reservedChainIdForFork1();
        assertEq(reservedChainIdForFork1, firstChainId);
        uint64 reservedChainIdForFork2 = ForkingManager(forkmanager)
            .reservedChainIdForFork2();
        assertEq(reservedChainIdForFork2, secondChainId);
    }

    function testExecuteForkRespectsTime() public {
        // reverts on empty proposal list
        vm.expectRevert("ForkingManager: fork not ready");
        forkmanager.executeFork1();

        // Mint and approve the arbitration fee for the test contract
        forkonomicToken.approve(address(forkmanager), arbitrationFee);
        vm.prank(address(this));
        forkonomicToken.mint(address(this), arbitrationFee);

        // Call the initiateFork function to create a new fork
        uint256 testTimestamp = 12354234;
        vm.warp(testTimestamp);
        forkmanager.initiateFork(
            disputeData,
            IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation,
                forkID: newForkID
            })
        );

        vm.expectRevert("ForkingManager: fork not ready");
        forkmanager.executeFork1();
        vm.warp(testTimestamp + forkmanager.forkPreparationTime() + 1);
        forkmanager.executeFork1();
    }

    function testExecuteForkCanOnlyExecutedOnce() public {
        // Mint and approve the arbitration fee for the test contract
        forkonomicToken.approve(address(forkmanager), arbitrationFee);
        vm.prank(address(this));
        forkonomicToken.mint(address(this), arbitrationFee);

        // Call the initiateFork function to create a new fork
        uint256 testTimestamp = 123454234;
        vm.warp(testTimestamp);
        forkmanager.initiateFork(
            disputeData,
            IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation,
                forkID: newForkID
            })
        );
        skip(forkmanager.forkPreparationTime() + 1);
        forkmanager.executeFork1();
        forkmanager.executeFork2();
        vm.expectRevert("No changes after forking");
        forkmanager.executeFork1();
    }

    function testRevertsSecondProposal() public {
        // Mint and approve the arbitration fee for the test contract
        forkonomicToken.approve(address(forkmanager), 3 * arbitrationFee);
        vm.prank(address(this));
        forkonomicToken.mint(address(this), 3 * arbitrationFee);

        // Call the initiateFork function to create a new fork
        disputeData.disputeContent = "0x1";
        forkmanager.initiateFork(
            disputeData,
            IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation,
                forkID: newForkID
            })
        );
        disputeData.disputeContent = "0x2";
        vm.expectRevert(bytes("ForkingManager: fork pending"));
        forkmanager.initiateFork(
            disputeData,
            IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation,
                forkID: newForkID
            })
        );
    }

    function testSetsCorrectGlobalExitRoot() public {
        // Set completely randcom exit hashes to make them non-zero
        bytes32 lastMainnetExitRoot = keccak256(abi.encode(2));
        bytes32 lastRollupExitRoot = keccak256(abi.encode(1));
        vm.prank(address(bridge));
        globalExitRoot.updateExitRoot(lastMainnetExitRoot);
        vm.prank(address(zkevm));
        globalExitRoot.updateExitRoot(lastRollupExitRoot);

        // Mint and approve the arbitration fee for the test contract
        forkonomicToken.approve(address(forkmanager), arbitrationFee);
        vm.prank(address(this));
        forkonomicToken.mint(address(this), arbitrationFee);

        // Call the initiateFork function to create a new fork
        uint256 testTimestamp = 12354234;
        vm.warp(testTimestamp);
        forkmanager.initiateFork(
            disputeData,
            IForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation,
                globalExitRootImplementation: newGlobalExitRootImplementation,
                verifier: newVerifierImplementation,
                forkID: newForkID
            })
        );

        vm.warp(testTimestamp + forkmanager.forkPreparationTime() + 1);
        forkmanager.executeFork1();
        (address child1, address child2) = globalExitRoot.getChildren();

         assertEq(
            IPolygonZkEVMGlobalExitRoot(globalExitRoot).lastMainnetExitRoot(),
            IPolygonZkEVMGlobalExitRoot(child1).lastMainnetExitRoot()
        );
        assertEq(
            IPolygonZkEVMGlobalExitRoot(globalExitRoot).lastRollupExitRoot(),
            IPolygonZkEVMGlobalExitRoot(child1).lastRollupExitRoot(),
            "lastRollupExitRoot not the same"
        );
        assertEq(
            IPolygonZkEVMGlobalExitRoot(globalExitRoot).getLastGlobalExitRoot(),
            IPolygonZkEVMGlobalExitRoot(child1).getLastGlobalExitRoot()
        );
        forkmanager.executeFork2();
         assertEq(
            IPolygonZkEVMGlobalExitRoot(globalExitRoot).lastMainnetExitRoot(),
            IPolygonZkEVMGlobalExitRoot(child2).lastMainnetExitRoot()
        );
        assertEq(
            IPolygonZkEVMGlobalExitRoot(globalExitRoot).lastRollupExitRoot(),
            IPolygonZkEVMGlobalExitRoot(child2).lastRollupExitRoot()
        );
    }
}
