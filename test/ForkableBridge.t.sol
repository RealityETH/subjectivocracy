pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ForkableBridge} from "../contracts/ForkableBridge.sol";
import {ForkableBridgeWrapper} from "./testcontract/ForkableBridgeWrapper.sol";
import {ForkonomicToken} from "../contracts/ForkonomicToken.sol";
import {IForkableBridge} from "../contracts/interfaces/IForkableBridge.sol";
import {IForkableStructure} from "../contracts/interfaces/IForkableStructure.sol";
import {ForkableGlobalExitRoot} from "../contracts/ForkableGlobalExitRoot.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IBasePolygonZkEVMGlobalExitRoot} from "@RealityETH/zkevm-contracts/contracts/inheritedMainContracts/PolygonZkEVMBridge.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract ForkableBridgeTest is Test {
    ForkableBridge public forkableBridge;
    IERC20Upgradeable public token = IERC20Upgradeable(address(0x987654));

    address public forkmanager = address(0x123);
    address public parentContract = address(0);
    address public polygonZkEVMaddress = address(0x789);
    address public gasTokenAddress = address(0xabc);
    address public admin = address(0xad);
    uint32 public networkID = 11;
    bool public isDeployedOnL2 = true;
    IBasePolygonZkEVMGlobalExitRoot public globalExitRootManager =
        IBasePolygonZkEVMGlobalExitRoot(address(0xdef));
    address public hardAssetManger = address(0xde34f);
    bytes32[32] public depositTreeHashes;

    function setUp() public {
        address bridgeImplementation = address(new ForkableBridge());
        forkableBridge = ForkableBridge(
            address(
                new TransparentUpgradeableProxy(bridgeImplementation, admin, "")
            )
        );
        forkableBridge.initialize(
            forkmanager,
            parentContract,
            networkID,
            globalExitRootManager,
            polygonZkEVMaddress,
            gasTokenAddress,
            isDeployedOnL2,
            hardAssetManger,
            2,
            depositTreeHashes
        );
    }

    function testInitialize() public {
        assertEq(forkableBridge.forkmanager(), forkmanager);
        assertEq(forkableBridge.parentContract(), parentContract);
        assertEq(forkableBridge.networkID(), networkID);
        assertEq(
            address(forkableBridge.globalExitRootManager()),
            address(globalExitRootManager)
        );
        assertEq(forkableBridge.polygonZkEVMaddress(), polygonZkEVMaddress);
        assertEq(forkableBridge.gasTokenAddress(), gasTokenAddress);
        assertEq(forkableBridge.isDeployedOnL2(), isDeployedOnL2);
    }

    function testCreateChildren() public {
        vm.expectRevert(IForkableStructure.OnlyForkManagerIsAllowed.selector);
        forkableBridge.createChildren();
        ForkableGlobalExitRoot exitRoot = new ForkableGlobalExitRoot();
        IERC20 gasToken = IERC20(address(gasTokenAddress));
        vm.mockCall(
            gasTokenAddress,
            abi.encodeWithSelector(
                gasToken.balanceOf.selector,
                address(forkableBridge)
            ),
            abi.encode(10)
        );

        forkableBridge.bridgeAsset(
            1,
            address(0x123),
            1,
            gasTokenAddress,
            false, // don't update the deposit tree, since we want to check that this happens during create children
            ""
        );
        bytes32 newDepositRoot = forkableBridge.getDepositRoot();

        // If globalExitRootManager is called, it should revert since there is no mock in place.
        vm.expectRevert();
        vm.prank(forkmanager);
        forkableBridge.createChildren();

        // Now, also wanna test that it does not revert, if the globalExitRootManager is called with the correct deposit root
        vm.mockCall(
            address(globalExitRootManager),
            abi.encodeWithSelector(
                exitRoot.updateExitRoot.selector,
                newDepositRoot
            ),
            ""
        );
        vm.prank(forkmanager);
        (address child1, address child2) = forkableBridge.createChildren();
        assertTrue(child1 != address(0));
        assertTrue(child2 != address(0));
    }

    function testMintForkableToken() public {
        uint32 originNetwork = 2;
        uint256 amount = 100 * (10 ** 18);
        bytes memory metadata = abi.encode("name", "symbol", uint8(18));
        address destinationAddress = address(this);
        bytes32 tokenInfoHash = keccak256(
            abi.encodePacked(originNetwork, token)
        );

        vm.expectRevert(IForkableStructure.OnlyParentIsAllowed.selector);
        forkableBridge.mintForkableToken(
            address(token),
            originNetwork,
            amount,
            metadata,
            destinationAddress
        );

        vm.prank(forkableBridge.parentContract());
        vm.expectRevert(IForkableBridge.InvalidOriginNetwork.selector);
        forkableBridge.mintForkableToken(
            address(token),
            networkID, // <-- this line is changed
            amount,
            metadata,
            destinationAddress
        );

        vm.prank(forkableBridge.parentContract());
        forkableBridge.mintForkableToken(
            address(token),
            originNetwork,
            amount,
            metadata,
            destinationAddress
        );

        address newWrappedToken = forkableBridge.tokenInfoToWrappedToken(
            tokenInfoHash
        );
        (
            uint32 originNetworkFromContract,
            address originTokenAddress
        ) = forkableBridge.wrappedTokenToTokenInfo(newWrappedToken);

        assertEq(originNetworkFromContract, originNetwork);
        assertEq(originTokenAddress, address(token));
        assertEq(
            IERC20Upgradeable(newWrappedToken).balanceOf(destinationAddress),
            amount
        );
    }

    function testBurnForkableToken() public {
        uint32 originNetwork = 2;
        uint256 amount = 100 * (10 ** 18);
        bytes memory metadata = abi.encode("name", "symbol", uint8(18));
        address destinationAddress = address(this);
        bytes32 tokenInfoHash = keccak256(
            abi.encodePacked(originNetwork, token)
        );

        vm.prank(forkableBridge.parentContract());
        forkableBridge.mintForkableToken(
            address(token),
            originNetwork,
            amount,
            metadata,
            destinationAddress
        );

        address newWrappedToken = forkableBridge.tokenInfoToWrappedToken(
            tokenInfoHash
        );
        (
            uint32 originNetworkFromContract,
            address originTokenAddress
        ) = forkableBridge.wrappedTokenToTokenInfo(newWrappedToken);

        assertEq(originNetworkFromContract, originNetwork);
        assertEq(originTokenAddress, address(token));
        assertEq(
            IERC20Upgradeable(newWrappedToken).balanceOf(destinationAddress),
            amount
        );

        vm.expectRevert(IForkableStructure.OnlyParentIsAllowed.selector);
        forkableBridge.burnForkableTokens(
            destinationAddress,
            originTokenAddress,
            originNetworkFromContract,
            amount
        );
        vm.prank(forkableBridge.parentContract());
        vm.expectRevert(bytes("ERC20: burn amount exceeds balance"));
        forkableBridge.burnForkableTokens(
            destinationAddress,
            originTokenAddress,
            originNetworkFromContract,
            amount + 1
        );
        vm.prank(forkableBridge.parentContract());
        forkableBridge.burnForkableTokens(
            destinationAddress,
            originTokenAddress,
            originNetworkFromContract,
            amount
        );

        assertEq(
            IERC20Upgradeable(newWrappedToken).balanceOf(destinationAddress),
            0
        );
    }

    function testSplitTokenIntoChildTokens() public {
        // Setup parameters
        uint32 originNetwork = 2;
        uint256 amount = 100 * (10 ** 18);
        bytes memory metadata = abi.encode("name", "symbol", uint8(18));
        address destinationAddress = address(this);
        bytes32 tokenInfoHash = keccak256(
            abi.encodePacked(originNetwork, token)
        );

        // Testing revert if children are not yet created
        vm.expectRevert(IForkableStructure.OnlyAfterForking.selector);

        forkableBridge.splitTokenIntoChildToken(address(token), amount, true);

        vm.prank(forkableBridge.forkmanager());
        (address child1, address child2) = forkableBridge.createChildren();

        // Create forkable token
        vm.prank(forkableBridge.parentContract());
        forkableBridge.mintForkableToken(
            address(token),
            originNetwork,
            amount,
            metadata,
            destinationAddress
        );

        address forkableToken = forkableBridge.tokenInfoToWrappedToken(
            tokenInfoHash
        );

        // initialize the child contracts to set the parent contract
        ForkableBridge(child1).initialize(
            forkmanager,
            address(forkableBridge),
            networkID,
            globalExitRootManager,
            polygonZkEVMaddress,
            gasTokenAddress,
            isDeployedOnL2,
            hardAssetManger,
            0,
            depositTreeHashes
        );
        ForkableBridge(child2).initialize(
            forkmanager,
            address(forkableBridge),
            networkID,
            globalExitRootManager,
            polygonZkEVMaddress,
            gasTokenAddress,
            isDeployedOnL2,
            hardAssetManger,
            0,
            depositTreeHashes
        );

        // splitting fails, if sender does not have the funds
        vm.prank(address(0x234234));
        vm.expectRevert(bytes("ERC20: burn amount exceeds balance"));
        forkableBridge.splitTokenIntoChildToken(forkableToken, amount, true);

        // Split the token
        forkableBridge.splitTokenIntoChildToken(forkableToken, amount, true);

        // Assert token balances
        address forkableTokenChild1 = ForkableBridge(child1)
            .tokenInfoToWrappedToken(tokenInfoHash);
        address forkableTokenChild2 = ForkableBridge(child2)
            .tokenInfoToWrappedToken(tokenInfoHash);
        uint256 child1Balance = IERC20Upgradeable(forkableTokenChild1)
            .balanceOf(destinationAddress);
        uint256 child2Balance = IERC20Upgradeable(forkableTokenChild2)
            .balanceOf(destinationAddress);
        assertEq(child1Balance, amount);
        assertEq(child2Balance, amount);

        // Assert token was burned from the parent contract
        uint256 parentBalance = IERC20Upgradeable(forkableToken).balanceOf(
            destinationAddress
        );
        assertEq(parentBalance, 0);
    }

    function testMergeChildTokens() public {
        // Setup parameters
        uint32 originNetwork = 2;
        uint256 amount = 100 * (10 ** 18);
        bytes memory metadata = abi.encode("name", "symbol", uint8(18));
        address destinationAddress = address(this);
        bytes32 tokenInfoHash = keccak256(
            abi.encodePacked(originNetwork, token)
        );

        vm.prank(forkableBridge.forkmanager());
        (address child1, address child2) = forkableBridge.createChildren();

        // Create forkable token
        vm.prank(forkableBridge.parentContract());
        forkableBridge.mintForkableToken(
            address(token),
            originNetwork,
            amount,
            metadata,
            destinationAddress
        );

        address forkableToken = forkableBridge.tokenInfoToWrappedToken(
            tokenInfoHash
        );
        for (uint256 i = 0; i < 32; i++) {
            depositTreeHashes[i] = forkableBridge.branch(i);
        }
        // initialize the child contracts to set the parent contract
        ForkableBridge(child1).initialize(
            forkmanager,
            address(forkableBridge),
            networkID,
            globalExitRootManager,
            polygonZkEVMaddress,
            gasTokenAddress,
            isDeployedOnL2,
            hardAssetManger,
            forkableBridge.lastUpdatedDepositCount(),
            depositTreeHashes
        );
        ForkableBridge(child2).initialize(
            forkmanager,
            address(forkableBridge),
            networkID,
            globalExitRootManager,
            polygonZkEVMaddress,
            gasTokenAddress,
            isDeployedOnL2,
            hardAssetManger,
            forkableBridge.lastUpdatedDepositCount(),
            depositTreeHashes
        );

        // Split the token
        forkableBridge.splitTokenIntoChildToken(forkableToken, amount, true);

        // Only parent can merge
        vm.expectRevert(IForkableStructure.OnlyAfterForking.selector);

        ForkableBridge(child1).mergeChildTokens(forkableToken, amount + 1);

        // Merge the token
        vm.expectRevert(bytes("ERC20: burn amount exceeds balance"));
        forkableBridge.mergeChildTokens(forkableToken, amount + 1);

        forkableBridge.mergeChildTokens(forkableToken, amount);

        // Assert token balances
        address forkableTokenChild1 = ForkableBridge(child1)
            .tokenInfoToWrappedToken(tokenInfoHash);
        address forkableTokenChild2 = ForkableBridge(child2)
            .tokenInfoToWrappedToken(tokenInfoHash);
        uint256 child1Balance = IERC20Upgradeable(forkableTokenChild1)
            .balanceOf(destinationAddress);
        uint256 child2Balance = IERC20Upgradeable(forkableTokenChild2)
            .balanceOf(destinationAddress);
        assertEq(child1Balance, 0);
        assertEq(child2Balance, 0);

        // Assert token was burned from the parent contract
        uint256 parentBalance = IERC20Upgradeable(forkableToken).balanceOf(
            destinationAddress
        );
        assertEq(parentBalance, amount);
    }

    function testNoDepostOrClaimingAfterForking() public {
        ForkableGlobalExitRoot exitRoot = new ForkableGlobalExitRoot();
        vm.mockCall(
            address(globalExitRootManager),
            abi.encodeWithSelector(
                exitRoot.updateExitRoot.selector,
                bytes32("0")
            ),
            ""
        );

        vm.prank(forkableBridge.forkmanager());
        forkableBridge.createChildren();

        vm.expectRevert(IForkableStructure.NoChangesAfterForking.selector);
        forkableBridge.bridgeAsset(
            12,
            address(0x3),
            15,
            address(0x3),
            true,
            bytes("0x3453")
        );

        vm.expectRevert(IForkableStructure.NoChangesAfterForking.selector);
        forkableBridge.bridgeMessage(2, address(0x45), false, bytes("0x3453"));

        bytes32[32] memory smtProof;
        vm.expectRevert(IForkableStructure.NoChangesAfterForking.selector);
        forkableBridge.claimMessage(
            smtProof,
            2,
            bytes32("0x1233"),
            bytes32("0x1233"),
            3,
            address(0x1232),
            12,
            address(0x1231),
            123,
            bytes("0x")
        );

        vm.expectRevert(IForkableStructure.NoChangesAfterForking.selector);
        forkableBridge.claimAsset(
            smtProof,
            32,
            bytes32("0x1233"),
            bytes32("0x1233"),
            3,
            address(0x1232),
            12,
            address(0x1231),
            123,
            bytes("0x")
        );
    }

    function testTransferHardAssetsToChild() public {
        ERC20PresetMinterPauser erc20Token = new ERC20PresetMinterPauser(
            "Test",
            "TST"
        );
        uint256 amount = 100 * (10 ** 18);
        address to = address(this);
        erc20Token.mint(to, amount);
        erc20Token.approve(address(forkableBridge), amount);
        forkableBridge.bridgeAsset(
            1,
            to,
            amount,
            address(erc20Token),
            false,
            ""
        );
        vm.expectRevert(IForkableStructure.OnlyAfterForking.selector);
        vm.prank(hardAssetManger);
        forkableBridge.transferHardAssetsToChild(
            address(erc20Token),
            amount,
            to
        );

        ForkableGlobalExitRoot exitRoot = new ForkableGlobalExitRoot();
        vm.mockCall(
            address(globalExitRootManager),
            abi.encodeWithSelector(
                exitRoot.updateExitRoot.selector,
                bytes32("0")
            ),
            ""
        );
        vm.prank(forkableBridge.forkmanager());
        (address child1, address child2) = forkableBridge.createChildren();

        // initialize the child contracts to set the parent contract
        ForkableBridge(child1).initialize(
            forkmanager,
            address(forkableBridge),
            networkID,
            globalExitRootManager,
            polygonZkEVMaddress,
            gasTokenAddress,
            isDeployedOnL2,
            hardAssetManger,
            forkableBridge.lastUpdatedDepositCount(),
            depositTreeHashes
        );
        ForkableBridge(child2).initialize(
            forkmanager,
            address(forkableBridge),
            networkID,
            globalExitRootManager,
            polygonZkEVMaddress,
            gasTokenAddress,
            isDeployedOnL2,
            hardAssetManger,
            forkableBridge.lastUpdatedDepositCount(),
            depositTreeHashes
        );

        vm.expectRevert(IForkableBridge.NotAuthorized.selector);
        forkableBridge.transferHardAssetsToChild(
            address(erc20Token),
            amount,
            to
        );

        vm.expectRevert(IForkableBridge.GasTokenIsNotHardAsset.selector);
        vm.prank(hardAssetManger);
        forkableBridge.transferHardAssetsToChild(
            address(gasTokenAddress),
            amount,
            child2
        );
        vm.expectRevert(
            IForkableBridge.InvalidDestinationForHardAsset.selector
        );
        vm.prank(hardAssetManger);
        forkableBridge.transferHardAssetsToChild(
            address(erc20Token),
            amount,
            address(0x23453465)
        );
        assertEq(erc20Token.balanceOf(address(forkableBridge)), amount);

        vm.prank(hardAssetManger);
        forkableBridge.transferHardAssetsToChild(
            address(erc20Token),
            amount,
            child2
        );

        assertEq(erc20Token.balanceOf(child2), amount);
        assertEq(erc20Token.balanceOf(address(forkableBridge)), 0);
    }

    function testSendForkonomicTokensToChildren() public {
        address forkonomicTokenImplementation = address(new ForkonomicToken());
        ForkonomicToken erc20GasToken = ForkonomicToken(
            address(
                new TransparentUpgradeableProxy(
                    forkonomicTokenImplementation,
                    admin,
                    ""
                )
            )
        );
        erc20GasToken.initialize(
            forkmanager,
            address(0x0),
            address(this),
            "GASTOKEN",
            "FORK"
        );
        address bridgeImplementation = address(new ForkableBridgeWrapper());
        ForkableBridgeWrapper forkableBridge2 = ForkableBridgeWrapper(
            address(
                new TransparentUpgradeableProxy(bridgeImplementation, admin, "")
            )
        );
        forkableBridge2.initialize(
            forkmanager,
            parentContract,
            networkID,
            globalExitRootManager,
            polygonZkEVMaddress,
            address(erc20GasToken),
            isDeployedOnL2,
            hardAssetManger,
            2,
            depositTreeHashes
        );
        // Let's start by minting some tokens to our contract
        uint256 mintAmount = 1000 * (10 ** 18);
        erc20GasToken.mint(address(forkableBridge2), mintAmount);

        // Now, call the function as the forkmanager
        vm.expectRevert(IForkableStructure.OnlyAfterForking.selector);

        vm.prank(forkmanager);
        forkableBridge2.sendForkonomicTokensToChild(10, true, false);
        vm.expectRevert(IForkableStructure.OnlyAfterForking.selector);

        vm.prank(forkmanager);
        forkableBridge2.sendForkonomicTokensToChild(10, true, false);

        // Create initiate the forking process and create children
        ForkableGlobalExitRoot exitRoot = new ForkableGlobalExitRoot();
        vm.mockCall(
            address(globalExitRootManager),
            abi.encodeWithSelector(
                exitRoot.updateExitRoot.selector,
                bytes32("0")
            ),
            ""
        );
        vm.prank(forkableBridge2.forkmanager());
        (address child1, address child2) = forkableBridge2.createChildren();

        // The initial balances
        uint256 initialBridgeBalance = erc20GasToken.balanceOf(
            address(forkableBridge2)
        );

        // Make sure our initial balances are correct
        assertEq(initialBridgeBalance, mintAmount);
        assertEq(erc20GasToken.balanceOf(child1), 0);
        assertEq(erc20GasToken.balanceOf(child2), 0);

        vm.prank(forkmanager);
        (address forkonomicToken1, address forkonomicToken2) = erc20GasToken
            .createChildren();
        ForkonomicToken(forkonomicToken1).initialize(
            forkmanager,
            address(this),
            address(erc20GasToken),
            "ForkonomicToken",
            "FTK"
        );
        ForkonomicToken(forkonomicToken2).initialize(
            forkmanager,
            address(this),
            address(erc20GasToken),
            "ForkonomicToken",
            "FTK"
        );
        // Now, call the function as the forkmanager
        uint256 amount = erc20GasToken.balanceOf(address(forkableBridge2));
        vm.prank(forkmanager);
        forkableBridge2.sendForkonomicTokensToChild(amount, true, false);
        vm.prank(forkmanager);
        forkableBridge2.sendForkonomicTokensToChild(amount, false, true);

        // Check that the tokens were transferred correctly
        assertEq(
            IERC20(forkonomicToken1).balanceOf(child1),
            initialBridgeBalance
        );
        assertEq(
            IERC20(forkonomicToken2).balanceOf(child2),
            initialBridgeBalance
        );
    }
}

contract ForkableBridgeWrapperTest is Test {
    ForkableBridgeWrapper public forkableBridge;
    IERC20Upgradeable public token = IERC20Upgradeable(address(0x987654));

    address public forkmanager = address(0x123);
    address public parentContract = address(0);
    address public polygonZkEVMaddress = address(0x789);
    address public gasTokenAddress = address(0xabc);
    uint32 public networkID = 11;
    bool public isDeployedOnL2 = true;
    IBasePolygonZkEVMGlobalExitRoot public globalExitRootManager =
        IBasePolygonZkEVMGlobalExitRoot(address(0xdef));
    address public hardAssetManger = address(0xde34f);
    bytes32[32] public depositTreeHashes;
    address public admin = address(0xad);

    function setUp() public {
        address bridgeImplementation = address(new ForkableBridgeWrapper());
        forkableBridge = ForkableBridgeWrapper(
            address(
                new TransparentUpgradeableProxy(bridgeImplementation, admin, "")
            )
        );
        forkableBridge.initialize(
            forkmanager,
            parentContract,
            networkID,
            globalExitRootManager,
            polygonZkEVMaddress,
            gasTokenAddress,
            isDeployedOnL2,
            hardAssetManger,
            2,
            depositTreeHashes
        );
    }

    function testIsClaimedOnParent() public {
        uint256 index = 1;
        ForkableGlobalExitRoot exitRoot = new ForkableGlobalExitRoot();
        vm.mockCall(
            address(globalExitRootManager),
            abi.encodeWithSelector(
                exitRoot.updateExitRoot.selector,
                bytes32("0")
            ),
            ""
        );
        vm.prank(forkableBridge.forkmanager());
        (address child1, address child2) = forkableBridge.createChildren();

        // initialize the child contracts to set the parent contract
        ForkableBridge(child1).initialize(
            forkmanager,
            address(forkableBridge),
            networkID,
            globalExitRootManager,
            polygonZkEVMaddress,
            gasTokenAddress,
            isDeployedOnL2,
            hardAssetManger,
            forkableBridge.lastUpdatedDepositCount() + uint32(index),
            depositTreeHashes
        );
        ForkableBridge(child2).initialize(
            forkmanager,
            address(forkableBridge),
            networkID,
            globalExitRootManager,
            polygonZkEVMaddress,
            gasTokenAddress,
            isDeployedOnL2,
            hardAssetManger,
            forkableBridge.lastUpdatedDepositCount() + uint32(index),
            depositTreeHashes
        );
        assertEq(forkableBridge.isClaimed(index), false);
        assertEq(ForkableBridge(child1).isClaimed(index), false);
        assertEq(ForkableBridge(child2).isClaimed(index), false);

        ForkableBridgeWrapper(child2).setClaimedBit(index);

        assertEq(forkableBridge.isClaimed(index), false);
        assertEq(ForkableBridge(child1).isClaimed(index), false);
        assertEq(ForkableBridge(child2).isClaimed(index), true);

        forkableBridge.setClaimedBit(index);

        assertEq(ForkableBridge(child1).isClaimed(index), true);
        assertEq(ForkableBridge(child2).isClaimed(index), true);
    }

    function testIsClaimedOnParentIsConsideringLastDepositUpdate() public {
        uint256 index = 1;

        ForkableGlobalExitRoot exitRoot = new ForkableGlobalExitRoot();
        vm.mockCall(
            address(globalExitRootManager),
            abi.encodeWithSelector(
                exitRoot.updateExitRoot.selector,
                bytes32("0")
            ),
            ""
        );
        vm.prank(forkableBridge.forkmanager());
        (address child1, address child2) = forkableBridge.createChildren();

        // initialize the child contracts to set the parent contract
        ForkableBridgeWrapper(child1).initialize(
            forkmanager,
            address(forkableBridge),
            networkID,
            globalExitRootManager,
            polygonZkEVMaddress,
            gasTokenAddress,
            isDeployedOnL2,
            hardAssetManger,
            uint32(index + 10),
            depositTreeHashes
        );
        ForkableBridgeWrapper(child2).initialize(
            forkmanager,
            address(forkableBridge),
            networkID,
            globalExitRootManager,
            polygonZkEVMaddress,
            gasTokenAddress,
            isDeployedOnL2,
            hardAssetManger,
            uint32(index + 10),
            depositTreeHashes
        );
        assertEq(forkableBridge.isClaimed(index), false);
        assertEq(ForkableBridge(child1).isClaimed(index), false);
        assertEq(ForkableBridge(child2).isClaimed(index), false);

        uint32 nonReachedIndexInParent = 3;
        forkableBridge.setClaimedBit(nonReachedIndexInParent);
        assertEq(
            ForkableBridge(child1).isClaimed(nonReachedIndexInParent),
            false
        );
        assertEq(
            ForkableBridge(child2).isClaimed(nonReachedIndexInParent),
            false
        );

        ForkableBridgeWrapper(child2).setClaimedBit(nonReachedIndexInParent);
        assertEq(
            ForkableBridge(child2).isClaimed(nonReachedIndexInParent),
            true
        );
    }

    function testSetAndCheckClaimed() public {
        uint256 index = 1;
        ForkableGlobalExitRoot exitRoot = new ForkableGlobalExitRoot();
        vm.mockCall(
            address(globalExitRootManager),
            abi.encodeWithSelector(
                exitRoot.updateExitRoot.selector,
                bytes32("0")
            ),
            ""
        );
        vm.prank(forkableBridge.forkmanager());
        (address child1, address child2) = forkableBridge.createChildren();

        // initialize the child contracts to set the parent contract
        ForkableBridge(child1).initialize(
            forkmanager,
            address(forkableBridge),
            networkID,
            globalExitRootManager,
            polygonZkEVMaddress,
            gasTokenAddress,
            isDeployedOnL2,
            hardAssetManger,
            forkableBridge.lastUpdatedDepositCount() + uint32(index),
            depositTreeHashes
        );
        ForkableBridge(child2).initialize(
            forkmanager,
            address(forkableBridge),
            networkID,
            globalExitRootManager,
            polygonZkEVMaddress,
            gasTokenAddress,
            isDeployedOnL2,
            hardAssetManger,
            forkableBridge.lastUpdatedDepositCount() + uint32(index),
            depositTreeHashes
        );

        assertEq(forkableBridge.isClaimed(index), false);
        assertEq(ForkableBridge(child1).isClaimed(index), false);
        assertEq(ForkableBridge(child2).isClaimed(index), false);

        forkableBridge.setClaimedBit(index);

        bytes4 selector = bytes4(keccak256("AlreadyClaimed()"));
        vm.expectRevert(selector);
        forkableBridge.setAndCheckClaimed(index);
        vm.expectRevert(selector);
        ForkableBridgeWrapper(child1).setAndCheckClaimed(index);
        vm.expectRevert(selector);
        ForkableBridgeWrapper(child2).setAndCheckClaimed(index);

        // check that the _verify function within PolygonZkEVMBridge calls really
        // the _setAndCheckClaimed function of the ForkableBridge contract
        // and not the _setAndCheckClaimed function of the PolygonZkEVMBridge contract
        bytes32[32] memory smtProof;
        for (uint256 i = 0; i < 32; i++) {
            smtProof[i] = forkableBridge.branch(i);
        }
        vm.expectRevert(selector);
        // forkableBridgeWrapper.claimAsset will call the PolygonZkEVMBridge.claimAsset function
        ForkableBridgeWrapper(child1).claimAsset(
            smtProof,
            uint32(index),
            bytes32(0),
            bytes32(0),
            uint32(0),
            address(0x1),
            uint32(1),
            address(0),
            uint256(1),
            bytes("0x")
        );
    }
}
