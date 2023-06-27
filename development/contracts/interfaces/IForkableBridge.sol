pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import "@RealityETH/zkevm-contracts/contracts/interfaces/IBasePolygonZkEVMGlobalExitRoot.sol";
import "./IForkableStructure.sol";

interface IForkableBridge is IPolygonZkEVMBridge, IForkableStructure {
    function initialize(
        address _forkmanager,
        address _parentContract,
        uint32 _networkID,
        IBasePolygonZkEVMGlobalExitRoot _globalExitRootManager,
        address _polygonZkEVMaddress,
        address _gasTokenAddress,
        bool _isDeployedOnL2
    ) external;

    function createChildren(
        address implementation
    ) external returns (address, address);

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
    ) external;

    function mintForkableToken(
        ERC20 token,
        uint32 originNetwork,
        uint256 amount,
        bytes calldata metadata,
        address destinationAddress
    ) external;
}
