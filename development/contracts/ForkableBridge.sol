pragma solidity ^0.8.17;

import "@RealityETH/zkevm-contracts/contracts/inheritedMainContracts/PolygonZkEVMBridge.sol";
import "@RealityETH/zkevm-contracts/contracts/lib/TokenWrapped.sol";
import "./interfaces/IForkableBridge.sol";
import "./mixin/ForkableUUPS.sol";

contract ForkableBridge is IForkableBridge, ForkableUUPS,  PolygonZkEVMBridge {
    function initialize(
        address _forkmanager,
        address _parentContract,
        uint32 _networkID,
        IBasePolygonZkEVMGlobalExitRoot _globalExitRootManager,
        address _polygonZkEVMaddress,
        address _gasTokenAddress,
        bool _isDeployedOnL2
    ) external initializer {
        forkmanager = _forkmanager;
        parentContract = _parentContract;
        PolygonZkEVMBridge.initialize(
            _networkID, _globalExitRootManager, _polygonZkEVMaddress, _gasTokenAddress, _isDeployedOnL2
        );
        _setupRole(UPDATER, msg.sender);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Anyone can use their tokens to split the bridged tokens into the two corresponding children tokens
     * @param token token that should be split
     * @param originNetwork origin network of the token to be split
     * @param amount amount of tokens to be split
     */
    function splitTokenIntoChildTokens(ERC20 token, uint32 originNetwork, uint256 amount) external {
        require(children[0] != address(0), "Children not created yet");
        require(children[1] != address(0), "Children not created yet");
        require(wrappedTokenToTokenInfo[address(token)].originNetwork != 0, "Token not forkable");
        TokenWrapped(address(token)).burn(msg.sender, amount);
        bytes memory metadata = abi.encodePacked(token.name(), token.symbol(), token.decimals());
        ForkableBridge(children[0]).mintForkableToken(token, originNetwork, amount, metadata, msg.sender);
        ForkableBridge(children[1]).mintForkableToken(token, originNetwork, amount, metadata, msg.sender);
    }

    function createChildren(address implementation) external onlyForkManger returns (address, address) {
        return _createChildren(implementation);
    }

    function mintForkableToken(
        ERC20 token,
        uint32 originNetwork,
        uint256 amount,
        bytes calldata metadata,
        address destinationAddress
    ) external onlyParent {
        require(wrappedTokenToTokenInfo[address(token)].originNetwork != networkID, "Token is from this network");
        _issueBridgedTokens(originNetwork, address(token), metadata, destinationAddress, amount);
    }
}
