pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import "../development/contracts/ForkingManager.sol";
import "../development/contracts/ForkableBridge.sol";
import "../development/contracts/ForkableZkEVM.sol";
import "../development/contracts/ForkonomicToken.sol";
import "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMGlobalExitRoot.sol";
import "@RealityETH/zkevm-contracts/contracts/interfaces/IVerifierRollup.sol";
import "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract E2E is Test {
    ForkableBridge public bridge;
    ForkonomicToken public forkonomicToken;
    ForkingManager public forkmanager;
    ForkableZkEVM public zkevm;
    address public bridgeImplementation;
    address public forkmanagerImplementation;
    address public zkevmImplementation;
    address public forkonomicTokenImplementation;
    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address public governer =
        address(0x1234567890123456789012345678901234567891);
    IBasePolygonZkEVMGlobalExitRoot public globalExitMock =
        IBasePolygonZkEVMGlobalExitRoot(
            0x1234567890123456789012345678901234567892
        );
    IPolygonZkEVMGlobalExitRoot public globalExitMock2 =
        IPolygonZkEVMGlobalExitRoot(0x1234567890123456789012345678901234567893);
    bytes32 public genesisRoot =
        bytes32(
            0x827a9240c96ccb855e4943cc9bc49a50b1e91ba087007441a1ae5f9df8d1c57c
        );
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

    function bytesToAddress(bytes32 b) public pure returns (address) {
        return address(uint160(uint256(b)));
    }

    function setUp() public {
        bridgeImplementation = address(new ForkableBridge());
        bridge = ForkableBridge(
            address(new ERC1967Proxy(bridgeImplementation, ""))
        );
        forkmanagerImplementation = address(new ForkingManager());
        forkmanager = ForkingManager(
            address(new ERC1967Proxy(forkmanagerImplementation, ""))
        );
        zkevmImplementation = address(new ForkableZkEVM());
        zkevm = ForkableZkEVM(
            address(new ERC1967Proxy(zkevmImplementation, ""))
        );
        forkonomicTokenImplementation = address(new ForkonomicToken());
        forkonomicToken = ForkonomicToken(
            address(new ERC1967Proxy(forkonomicTokenImplementation, ""))
        );
        bridge.initialize(
            address(forkmanager),
            address(0x0),
            networkID,
            globalExitMock,
            address(zkevm),
            address(forkonomicToken),
            false
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
            globalExitMock2,
            IERC20Upgradeable(address(forkonomicToken)),
            rollupVerifierMock,
            IPolygonZkEVMBridge(address(bridge))
        );
        forkmanager.initialize(
            address(zkevm),
            address(bridge),
            address(forkonomicToken),
            address(0x0),
            arbitrationFee
        );
        forkonomicToken.initialize(
            address(forkmanager),
            address(0x0),
            address(this)
        );
    }

    function testForkConfigurationAndImplementations() public {
        // Setup new implementations for the fork
        address newBridgeImplementation = address(new ForkableBridge());
        address newForkmanagerImplementation = address(new ForkingManager());
        address newZkevmImplementation = address(new ForkableZkEVM());
        address newForkonomicTokenImplementation = address(
            new ForkonomicToken()
        );

        // Mint and approve the arbitration fee for the test contract
        forkonomicToken.approve(address(forkmanager), arbitrationFee);
        vm.prank(address(this));
        forkonomicToken.mint(address(this), arbitrationFee);

        address disputeContract = address(
            0x1234567890123456789012345678901234567894
        );
        bytes
            memory disputeData = "0x345678901234567890123456789012345678901234567890123456789012345678901234567890123456789";

        // Call the initiateFork function to create a new fork
        forkmanager.initiateFork(
            disputeContract,
            disputeData,
            ForkingManager.NewImplementations({
                bridgeImplementation: newBridgeImplementation,
                zkEVMImplementation: newZkevmImplementation,
                forkonomicTokenImplementation: newForkonomicTokenImplementation,
                forkingManagerImplementation: newForkmanagerImplementation
            })
        );

        // Fetch the children from the ForkingManager
        (address childForkmanager1, address childForkmanager2) = forkmanager
            .getChildren();

        // Assert that the fork managers match the ones we provided
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

        // Fetch the children from the ForkableZkEVM contract
        (address childZkevm1, address childZkevm2) = zkevm.getChildren();

        // Assert that the ZkEVM contracts match the ones we provided
        assertEq(
            bytesToAddress(vm.load(address(childZkevm1), _IMPLEMENTATION_SLOT)),
            zkevmImplementation
        );
        assertEq(
            bytesToAddress(vm.load(address(childZkevm2), _IMPLEMENTATION_SLOT)),
            newZkevmImplementation
        );

        // Fetch the children from the ForkonomicToken contract
        (
            address childForkonomicToken1,
            address childForkonomicToken2
        ) = forkonomicToken.getChildren();

        // Assert that the forkonomic tokens match the ones we provided
        assertEq(
            bytesToAddress(
                vm.load(address(childForkonomicToken1), _IMPLEMENTATION_SLOT)
            ),
            forkonomicTokenImplementation
        );
        assertEq(
            bytesToAddress(
                vm.load(address(childForkonomicToken2), _IMPLEMENTATION_SLOT)
            ),
            newForkonomicTokenImplementation
        );

        // Assert the dispute contract and call stored in the ForkingManager match the ones we provided
        assertEq(forkmanager.disputeContract(), disputeContract);
        assertEq(forkmanager.disputeCall(), disputeData);
    }
}
