pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IForkableBridge {

    function initialize(
        address _forkmanager,
        address _parentBridge
    ) external;

    /**
     * @notice allows the forkmanager to create the new children
     */
    function createChildren() external;

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

    function getChild(uint256 index) external view returns (address);
}
