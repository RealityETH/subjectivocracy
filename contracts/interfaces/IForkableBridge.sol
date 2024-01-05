// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {IBasePolygonZkEVMGlobalExitRoot} from "@RealityETH/zkevm-contracts/contracts/interfaces/IBasePolygonZkEVMGlobalExitRoot.sol";
import {IForkableStructure} from "./IForkableStructure.sol";

interface IForkableBridge is IForkableStructure, IPolygonZkEVMBridge {
    /// @dev Error thrown when activity is started by a non-authorized actor
    error NotAuthorized();
    /// @dev Error thrown when trying to send bridged tokens to a child contract
    error InvalidDestinationForHardAsset();
    /// @dev Error thrown when hardasset manager tries to send gas token to a child contract
    error GasTokenIsNotHardAsset();

    /**
     * @dev Function to initialize the contract
     * @param _forkmanager: address of the forkmanager contract
     * @param _parentContract: address of the parent contract
     * @param _networkID: network id of the network
     * @param _globalExitRootManager: address of the global exit root manager
     * @param _polygonZkEVMaddress: address of the polygonZkEVM contract
     * @param _gasTokenAddress: address of the gas token
     * @param _isDeployedOnL2: boolean to check if the contract is deployed on L2
     * @param hardAssetManger: address of the hardAssetManger, that can decided to which child the tokens should be sent
     */
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
        bytes32[32] calldata depositTreeHashes
    ) external;

    function getHardAssetManager() external view returns (address);

    function getLastUpdatedDepositCount() external view returns (uint32);

    function getBranch() external view returns (bytes32[32] memory);

    /**
     * @dev Function to create the children contracts
     */
    function createChildren() external returns (address, address);

    /**
     * @dev Anyone can use their tokens to split the bridged tokens into the two corresponding children tokens
     * @param token token that should be split
     * @param amount amount of tokens to be split
     */
    function splitTokenIntoChildToken(
        address token,
        uint256 amount,
        bool mintSecondChild
    ) external;

    /**
     * @dev Function to mint the forkable token by the parent contract
     * @param token: address of the token to be minted
     * @param originNetwork: origin network of the token to be minted
     *  @param amount: amount of tokens to be minted
     * @param metadata: metadata of the token to be minted
     * @param destinationAddress: address of the destination
     **/
    function mintForkableToken(
        address token,
        uint32 originNetwork,
        uint256 amount,
        bytes calldata metadata,
        address destinationAddress
    ) external;

    /**
     * @dev function to be called by the partent contract to burn forkable tokens issued by the bridge
     * function is used to reverse a splitting of tokens
     * @param user user address
     * @param originTokenAddress originTokenAddress of the wrapped token to be burned
     * @param originNetwork origin network of the wrapped token to be burned
     * @param amount amount of tokens to be burned
     */
    function burnForkableTokens(
        address user,
        address originTokenAddress,
        uint32 originNetwork,
        uint256 amount
    ) external;

    /**
     * @dev function to be called by the partent contract to burn forkable tokens issued by the bridge
     * function is used to reverse a splitting of tokens
     * @param token token address of token to be created
     * @param amount amount of tokens to be created
     */
    function mergeChildTokens(address token, uint256 amount) external;
}
