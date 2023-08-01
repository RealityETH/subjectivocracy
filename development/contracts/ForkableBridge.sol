pragma solidity ^0.8.17;

import {PolygonZkEVMBridge, IBasePolygonZkEVMGlobalExitRoot} from "@RealityETH/zkevm-contracts/contracts/inheritedMainContracts/PolygonZkEVMBridge.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TokenWrapped} from "@RealityETH/zkevm-contracts/contracts/lib/TokenWrapped.sol";
import {IForkableBridge} from "./interfaces/IForkableBridge.sol";
import {IForkonomicToken} from "./interfaces/IForkonomicToken.sol";
import {ForkableUUPS} from "./mixin/ForkableUUPS.sol";

contract ForkableBridge is IForkableBridge, ForkableUUPS, PolygonZkEVMBridge {
    bytes32 public constant HARD_ASSET_MANAGER_ROLE =
        keccak256("HARD_ASSET_MANAGER_ROLE");

    // @inheritdoc IForkableBridge
    function initialize(
        address _forkmanager,
        address _parentContract,
        uint32 _networkID,
        IBasePolygonZkEVMGlobalExitRoot _globalExitRootManager,
        address _polygonZkEVMaddress,
        address _gasTokenAddress,
        bool _isDeployedOnL2,
        address hardAssetManger,
        uint32 lastUpdatedDepositCount,
        bytes32[_DEPOSIT_CONTRACT_TREE_DEPTH] calldata depositTree
    ) public virtual initializer {
        ForkableUUPS.initialize(_forkmanager, _parentContract, msg.sender);
        PolygonZkEVMBridge.initialize(
            _networkID,
            _globalExitRootManager,
            _polygonZkEVMaddress,
            _gasTokenAddress,
            _isDeployedOnL2,
            lastUpdatedDepositCount,
            depositTree
        );
        _setupRole(HARD_ASSET_MANAGER_ROLE, hardAssetManger);
    }

    /**
     * @notice Function to send hard assets to the children-bridge contracts
     * @param token Address of the token
     * @param amount Amount of tokens to transfer
     * @param to Address to transfer the tokens to
     */
    function transferHardAssetsToChild(
        address token,
        uint256 amount,
        address to
    ) external {
        require(hasRole(HARD_ASSET_MANAGER_ROLE, msg.sender), "Not authorized");
        require(children[0] != address(0), "only after fork");
        require(to == children[0] || to == children[1], "Invalid to address");
        IERC20(token).transfer(to, amount);
    }

    /**
     * @notice Function to check if an index is claimed or not
     * @param index Index. function is overridden to check for a potential
     * claim in the parent contract
     * note: This function is recursive and could run into stack too deep issues
     * hence users need to claim their tokens before several forks happened.
     */
    function isClaimed(uint256 index) public view override returns (bool) {
        if (depositCount < index) {
            return false;
        }
        bool isClaimedInCurrentContract = PolygonZkEVMBridge.isClaimed(index);
        if (isClaimedInCurrentContract) {
            return true;
        }
        if (parentContract != address(0)) {
            // Also check the parent contract for claims if it is set
            return ForkableBridge(parentContract).isClaimed(index);
        } else {
            return false;
        }
    }

    /**
     * @notice Function to check that an index is not claimed and set it as claimed
     * @param index Index
     */
    function _setAndCheckClaimed(uint256 index) internal override {
        // Additional to the normal implemenation, we also check the parent contract
        // for already claimed indexes
        if (parentContract != address(0)) {
            if (ForkableBridge(parentContract).isClaimed(index)) {
                revert AlreadyClaimed();
            }
        }
        PolygonZkEVMBridge._setAndCheckClaimed(index);
    }

    // @inheritdoc IForkableBridge
    function createChildren(
        address implementation
    ) external onlyForkManger returns (address, address) {
        // process all pending deposits/messages before coping over the state root.
        updateGlobalExitRoot();
        return _createChildren(implementation);
    }

    // @inheritdoc IForkableBridge
    function mintForkableToken(
        address token,
        uint32 originNetwork,
        uint256 amount,
        bytes calldata metadata,
        address destinationAddress
    ) external onlyParent {
        require(originNetwork != networkID, "Token is from this network");
        _issueBridgedTokens(
            originNetwork,
            token,
            metadata,
            destinationAddress,
            amount
        );
    }

    // @inheritdoc IForkableBridge
    function splitTokenIntoChildTokens(address token, uint256 amount) external {
        require(children[0] != address(0), "Children not created yet");
        require(
            wrappedTokenToTokenInfo[token].originNetwork != 0,
            "Token not forkable"
        );
        TokenWrapped(token).burn(msg.sender, amount);
        bytes memory metadata = abi.encode(
            IERC20Metadata(token).name(),
            IERC20Metadata(token).symbol(),
            IERC20Metadata(token).decimals()
        );
        ForkableBridge(children[0]).mintForkableToken(
            wrappedTokenToTokenInfo[token].originTokenAddress,
            wrappedTokenToTokenInfo[token].originNetwork,
            amount,
            metadata,
            msg.sender
        );
        ForkableBridge(children[1]).mintForkableToken(
            wrappedTokenToTokenInfo[token].originTokenAddress,
            wrappedTokenToTokenInfo[token].originNetwork,
            amount,
            metadata,
            msg.sender
        );
    }

    // @inheritdoc IForkableBridge
    function burnForkableTokens(
        address user,
        address originTokenAddress,
        uint32 originNetwork,
        uint256 amount
    ) external onlyParent {
        bytes32 infoHash = keccak256(
            abi.encodePacked(originNetwork, originTokenAddress)
        );
        TokenWrapped(tokenInfoToWrappedToken[infoHash]).burn(user, amount);
    }

    // @inheritdoc IForkableBridge
    function mergeChildTokens(address token, uint256 amount) external {
        require(children[0] != address(0), "Children not created yet");
        require(
            wrappedTokenToTokenInfo[token].originNetwork != 0,
            "Token not forkable"
        );
        require(
            wrappedTokenToTokenInfo[token].originTokenAddress != address(0),
            "Token not issued before"
        );
        ForkableBridge(children[0]).burnForkableTokens(
            msg.sender,
            wrappedTokenToTokenInfo[token].originTokenAddress,
            wrappedTokenToTokenInfo[token].originNetwork,
            amount
        );

        ForkableBridge(children[1]).burnForkableTokens(
            msg.sender,
            wrappedTokenToTokenInfo[token].originTokenAddress,
            wrappedTokenToTokenInfo[token].originNetwork,
            amount
        );
        TokenWrapped(token).mint(msg.sender, amount);
    }

    /**
     * @dev Allows the forkmanager to take out the forkonomic tokens
     * and send them to the children-bridge contracts
     * Notice that forkonomic tokens are special, as they their main contract
     * is on L1, but they are still forkable tokens as all the tokens from L2.
     */
    function sendForkonomicTokensToChildren() public onlyForkManger {
        require(children[0] != address(0), "Children not created yet");
        IForkonomicToken(gasTokenAddress).splitTokensIntoChildTokens(
            IERC20(gasTokenAddress).balanceOf(address(this))
        );
        (address forkonomicToken1, address forkonomicToken2) = IForkonomicToken(
            gasTokenAddress
        ).getChildren();
        IERC20(forkonomicToken1).transfer(
            children[0],
            IERC20(forkonomicToken1).balanceOf(address(this))
        );
        IERC20(forkonomicToken2).transfer(
            children[1],
            IERC20(forkonomicToken2).balanceOf(address(this))
        );
    }

    /////////////////////////////////////////////////////
    // Overwriting function to disable them after forking
    /////////////////////////////////////////////////////

    function bridgeAsset(
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        address token,
        bool forceUpdateGlobalExitRoot,
        bytes calldata permitData
    )
        public
        payable
        override(PolygonZkEVMBridge, IPolygonZkEVMBridge)
        onlyBeforeForking
    {
        PolygonZkEVMBridge.bridgeAsset(
            destinationNetwork,
            destinationAddress,
            amount,
            token,
            forceUpdateGlobalExitRoot,
            permitData
        );
    }

    function bridgeMessage(
        uint32 destinationNetwork,
        address destinationAddress,
        bool forceUpdateGlobalExitRoot,
        bytes calldata metadata
    )
        public
        payable
        virtual
        override(PolygonZkEVMBridge, IPolygonZkEVMBridge)
        onlyBeforeForking
    {
        PolygonZkEVMBridge.bridgeMessage(
            destinationNetwork,
            destinationAddress,
            forceUpdateGlobalExitRoot,
            metadata
        );
    }

    function claimMessage(
        bytes32[_DEPOSIT_CONTRACT_TREE_DEPTH] calldata smtProof,
        uint32 index,
        bytes32 mainnetExitRoot,
        bytes32 rollupExitRoot,
        uint32 originNetwork,
        address originAddress,
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        bytes calldata metadata
    )
        public
        override(IPolygonZkEVMBridge, PolygonZkEVMBridge)
        onlyBeforeForking
    {
        PolygonZkEVMBridge.claimMessage(
            smtProof,
            index,
            mainnetExitRoot,
            rollupExitRoot,
            originNetwork,
            originAddress,
            destinationNetwork,
            destinationAddress,
            amount,
            metadata
        );
    }

    function claimAsset(
        bytes32[_DEPOSIT_CONTRACT_TREE_DEPTH] calldata smtProof,
        uint32 index,
        bytes32 mainnetExitRoot,
        bytes32 rollupExitRoot,
        uint32 originNetwork,
        address originTokenAddress,
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        bytes calldata metadata
    )
        public
        override(IPolygonZkEVMBridge, PolygonZkEVMBridge)
        onlyBeforeForking
    {
        PolygonZkEVMBridge.claimAsset(
            smtProof,
            index,
            mainnetExitRoot,
            rollupExitRoot,
            originNetwork,
            originTokenAddress,
            destinationNetwork,
            destinationAddress,
            amount,
            metadata
        );
    }
}
