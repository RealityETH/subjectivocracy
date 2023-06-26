pragma solidity ^0.8.17;

import "@RealityETH/zkevm-contracts/contracts/PolygonZkEVMBridge.sol";
import "@RealityETH/zkevm-contracts/contracts/lib/TokenWrapped.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "./interfaces/IForkableBridge.sol";
import "./mixin/ForkStructure.sol";

contract ForkableBridge is PolygonZkEVMBridge, IForkableBridge, ForkStructure {
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
            _networkID,
            _globalExitRootManager,
            _polygonZkEVMaddress,
            _gasTokenAddress,
            _isDeployedOnL2
        );
    }

    /**
     * @notice Allows the forkmanager to create the new children
     */
    function createChildren()
        external
        onlyForkManger
        returns (address, address)
    {
        address forkableBridge = ClonesUpgradeable.clone(address(this));
        children[0] = forkableBridge;
        forkableBridge = ClonesUpgradeable.clone(address(this));
        children[1] = forkableBridge;
        return (children[0], children[1]);
    }

    /**
     * @notice Anyone can use their tokens to split the bridged tokens into the two corresponding children tokens
     * @param token token that should be split
     * @param originNetwork origin network of the token to be split
     * @param amount amount of tokens to be split
     */
    function splitTokenIntoChildTokens(
        ERC20 token,
        uint32 originNetwork,
        uint256 amount
    ) external {
        require(children[0] != address(0), "Children not created yet");
        require(children[1] != address(0), "Children not created yet");
        require(
            wrappedTokenToTokenInfo[address(token)].originNetwork != 0,
            "Token not forkable"
        );
        TokenWrapped(address(token)).burn(msg.sender, amount);
        bytes memory metadata = abi.encodePacked(
            token.name(),
            token.symbol(),
            token.decimals()
        );
        ForkableBridge(children[0]).mintForkableToken(
            token,
            originNetwork,
            amount,
            metadata,
            msg.sender
        );
        ForkableBridge(children[1]).mintForkableToken(
            token,
            originNetwork,
            amount,
            metadata,
            msg.sender
        );
    }

    function mintForkableToken(
        ERC20 token,
        uint32 originNetwork,
        uint256 amount,
        bytes calldata metadata,
        address destinationAddress
    ) external onlyParent {
        require(
            wrappedTokenToTokenInfo[address(token)].originNetwork != networkID,
            "Token is from this network"
        );
        issueBridgedTokens(
            originNetwork,
            address(token),
            metadata,
            destinationAddress,
            amount
        );
    }
}
