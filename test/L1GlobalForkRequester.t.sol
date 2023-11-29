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

import {L1GlobalForkRequester} from "../contracts/L1GlobalForkRequester.sol";
import {ExampleMoneyBoxUser} from "./testcontract/ExampleMoneyBoxUser.sol";

contract L1GlobalForkRequesterTest is Test {
    L1GlobalForkRequester public l1GlobalForkRequester =
        new L1GlobalForkRequester();

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
    address public chainIdManager;
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
    uint64 public newForkID = 4;
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
    uint64 public initialChainId = 1;
    uint64 public firstChainId = 1;
    uint64 public secondChainId = 2;

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
    bytes32 public disputeContent = "0x34567890129";
    bool public isL1 = true;

    event Transfer(address indexed from, address indexed to, uint256 tokenId);

    function bytesToAddress(bytes32 b) public pure returns (address) {
        return address(uint160(uint256(b)));
    }

    // TODO: This setup is duplicated with the ForkingManager tests
    // It might be good to pull it out somewhere.
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

        chainIdManager = address(new ChainIdManager(initialChainId));
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
        forkmanager.initialize(
            address(zkevm),
            address(bridge),
            address(forkonomicToken),
            address(0x0),
            address(globalExitRoot),
            arbitrationFee,
            chainIdManager
        );
        forkonomicToken.initialize(
            address(forkmanager),
            address(0x0),
            address(this),
            "Fork",
            "FORK"
        );
    }

    function testReceivePayment() public {
        uint256 fee = forkmanager.arbitrationFee();

        ExampleMoneyBoxUser exampleMoneyBoxUser = new ExampleMoneyBoxUser();
        // Receive a payment from a MoneyBox

        address l2Requester = address(0xbabe01);
        bytes32 requestId = bytes32("0xc0ffee01");
        bytes32 salt = keccak256(abi.encodePacked(l2Requester, requestId));
        address moneyBoxAddress = exampleMoneyBoxUser.calculateMoneyBoxAddress(
            address(l1GlobalForkRequester),
            salt,
            address(forkonomicToken)
        );

        vm.prank(address(this));
        forkonomicToken.mint(address(this), fee);

        vm.prank(address(this));
        forkonomicToken.transfer(moneyBoxAddress, fee);

        assertEq(
            address(forkmanager.forkonomicToken()),
            address(forkonomicToken)
        );
        assertTrue(forkmanager.canFork());
        assertFalse(forkmanager.isForkingInitiated());
        assertFalse(forkmanager.isForkingExecuted());

        l1GlobalForkRequester.handlePayment(
            address(forkonomicToken),
            l2Requester,
            requestId
        );

        assertTrue(forkmanager.isForkingInitiated());
        assertFalse(forkmanager.isForkingExecuted());
    }

    function testReceiveInsufficientPayment() public {
        uint256 fee = forkmanager.arbitrationFee() - 1;

        ExampleMoneyBoxUser exampleMoneyBoxUser = new ExampleMoneyBoxUser();
        // Receive a payment from a MoneyBox

        address l2Requester = address(0xbabe01);
        bytes32 requestId = bytes32("0xc0ffee01");
        bytes32 salt = keccak256(abi.encodePacked(l2Requester, requestId));
        address moneyBoxAddress = exampleMoneyBoxUser.calculateMoneyBoxAddress(
            address(l1GlobalForkRequester),
            salt,
            address(forkonomicToken)
        );

        vm.prank(address(this));
        forkonomicToken.mint(address(this), fee);

        vm.prank(address(this));
        forkonomicToken.transfer(moneyBoxAddress, fee);

        assertEq(
            address(forkmanager.forkonomicToken()),
            address(forkonomicToken)
        );
        assertTrue(forkmanager.canFork());

        l1GlobalForkRequester.handlePayment(
            address(forkonomicToken),
            l2Requester,
            requestId
        );
        assertFalse(forkmanager.isForkingInitiated());

        (
            uint256 amount,
            uint256 amountRemainingY,
            uint256 amountRemainingN
        ) = l1GlobalForkRequester.failedRequests(
                address(forkonomicToken),
                l2Requester,
                requestId
            );
        assertEq(amount, fee);
        assertEq(amountRemainingY, 0);
        assertEq(amountRemainingN, 0);
    }

    function testHandleOtherRequestForksFirst() public {
        uint256 fee = forkmanager.arbitrationFee();

        ExampleMoneyBoxUser exampleMoneyBoxUser = new ExampleMoneyBoxUser();
        // Receive a payment from a MoneyBox

        address l2Requester = address(0xbabe01);
        bytes32 requestId = bytes32("0xc0ffee01");
        bytes32 salt = keccak256(abi.encodePacked(l2Requester, requestId));
        address moneyBoxAddress = exampleMoneyBoxUser.calculateMoneyBoxAddress(
            address(l1GlobalForkRequester),
            salt,
            address(forkonomicToken)
        );

        vm.prank(address(this));
        forkonomicToken.mint(address(this), fee);

        vm.prank(address(this));
        forkonomicToken.transfer(moneyBoxAddress, fee);

        assertEq(
            address(forkmanager.forkonomicToken()),
            address(forkonomicToken)
        );
        assertTrue(forkmanager.canFork());

        {
            // Someone else starts and executes a fork before we can handle our payment
            vm.prank(address(this));
            forkonomicToken.mint(address(this), fee);
            vm.prank(address(this));
            forkonomicToken.approve(address(forkmanager), fee);
            // Assume the data contains the questionId and pass it directly to the forkmanager in the fork request
            IForkingManager.NewImplementations memory newImplementations;
            IForkingManager.DisputeData memory disputeData = IForkingManager
                .DisputeData(false, address(this), requestId);
            forkmanager.initiateFork(disputeData, newImplementations);
        }

        // Our handlePayment will fail and leave our money sitting in failedRequests
        uint256 balBeforeHandle = forkonomicToken.balanceOf(
            address(l1GlobalForkRequester)
        );

        l1GlobalForkRequester.handlePayment(
            address(forkonomicToken),
            l2Requester,
            requestId
        );
        (
            uint256 amount,
            uint256 amountRemainingY,
            uint256 amountRemainingN
        ) = l1GlobalForkRequester.failedRequests(
                address(forkonomicToken),
                l2Requester,
                requestId
            );
        assertEq(amount, fee);
        assertEq(amountRemainingY, 0);
        assertEq(amountRemainingN, 0);

        uint256 balAfterHandle = forkonomicToken.balanceOf(
            address(l1GlobalForkRequester)
        );
        assertEq(balBeforeHandle + amount, balAfterHandle);

        vm.expectRevert("Token not forked");
        l1GlobalForkRequester.splitTokensIntoChildTokens(
            address(forkonomicToken),
            l2Requester,
            requestId
        );

        // Execute the other guy's fork
        skip(forkmanager.forkPreparationTime() + 1);
        forkmanager.executeFork1();
        forkmanager.executeFork2();

        {
            uint256 balBeforeSplit = forkonomicToken.balanceOf(
                address(l1GlobalForkRequester)
            );
            l1GlobalForkRequester.splitTokensIntoChildTokens(
                address(forkonomicToken),
                l2Requester,
                requestId
            );
            uint256 balAfterSplit = forkonomicToken.balanceOf(
                address(l1GlobalForkRequester)
            );
            assertEq(balAfterSplit + amount, balBeforeSplit);
        }

        // The children should now both have the funds we split
        (address childToken1, address childToken2) = forkonomicToken
            .getChildren();
        assertEq(
            ForkonomicToken(childToken1).balanceOf(
                address(l1GlobalForkRequester)
            ),
            amount
        );
        assertEq(
            ForkonomicToken(childToken2).balanceOf(
                address(l1GlobalForkRequester)
            ),
            amount
        );

        // Now we should be able to return the tokens on the child chain
        l1GlobalForkRequester.returnTokens(
            address(childToken1),
            l2Requester,
            requestId
        );
        (uint256 amountChild1, , ) = l1GlobalForkRequester.failedRequests(
            childToken1,
            l2Requester,
            requestId
        );
        (uint256 amountChild2, , ) = l1GlobalForkRequester.failedRequests(
            childToken2,
            l2Requester,
            requestId
        );

        assertEq(
            ForkonomicToken(childToken2).balanceOf(
                address(l1GlobalForkRequester)
            ),
            amount
        );

        assertEq(amountChild1, 0);
        assertEq(amountChild2, amount);

        // TODO: This breaks due to _CURRENT_SUPPORTED_NETWORKS which is capped at 2
        // Raise this if we need it, alternatively maybe it's unrelated to Chain ID and it doesn't need to change when the fork does.

        // l1GlobalForkRequester.returnTokens(address(childToken2), l2Requester, requestId);
        // (amountChild2, , ) = l1GlobalForkRequester.failedRequests(childToken2, l2Requester, requestId);
        // assertEq(amountChild2, 0);
    }
}
