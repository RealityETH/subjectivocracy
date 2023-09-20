// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
import {PolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/inheritedMainContracts/PolygonZkEVMBridge.sol";
import {TokenWrapped} from "@RealityETH/zkevm-contracts/contracts/lib/TokenWrapped.sol";
import {ForkableBridge} from "../ForkableBridge.sol";
import {IForkonomicToken} from "../interfaces/IForkonomicToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

library BridgeAssetOperations {
    /**
     * @notice Function to merge tokens from children-bridge contracts
     * @param token Address of the token
     * @param amount Amount of tokens to transfer
     * @param tokenInfo Information about the token
     * @param child0 Address of the first child-bridge contract
     * @param child1 Address of the second child-bridge contract
     */
    function mergeChildTokens(
        address token,
        uint256 amount,
        PolygonZkEVMBridge.TokenInformation memory tokenInfo,
        address child0,
        address child1
    ) public {
        require(tokenInfo.originNetwork != 0, "Token not forkable");
        require(
            tokenInfo.originTokenAddress != address(0),
            "Token not issued before"
        );
        ForkableBridge(child0).burnForkableTokens(
            msg.sender,
            tokenInfo.originTokenAddress,
            tokenInfo.originNetwork,
            amount
        );

        ForkableBridge(child1).burnForkableTokens(
            msg.sender,
            tokenInfo.originTokenAddress,
            tokenInfo.originNetwork,
            amount
        );
        TokenWrapped(token).mint(msg.sender, amount);
    }

    /**
     * @notice Function to split tokens into children-bridge contracts
     * @param token Address of the token
     * @param amount Amount of tokens to transfer
     * @param tokenInfo Information about the token
     * @param child0 Address of the first child-bridge contract
     * @param child1 Address of the second child-bridge contract
     */
    function splitTokenIntoChildTokens(
        address token,
        uint256 amount,
        PolygonZkEVMBridge.TokenInformation memory tokenInfo,
        address child0,
        address child1
    ) external {
        require(tokenInfo.originNetwork != 0, "Token not forkable");
        TokenWrapped(token).burn(msg.sender, amount);
        bytes memory metadata = abi.encode(
            IERC20Metadata(token).name(),
            IERC20Metadata(token).symbol(),
            IERC20Metadata(token).decimals()
        );
        ForkableBridge(child0).mintForkableToken(
            tokenInfo.originTokenAddress,
            tokenInfo.originNetwork,
            amount,
            metadata,
            msg.sender
        );
        ForkableBridge(child1).mintForkableToken(
            tokenInfo.originTokenAddress,
            tokenInfo.originNetwork,
            amount,
            metadata,
            msg.sender
        );
    }

    /**
     * @notice Function to send tokens into children-bridge contracts by the admin
     * @param gasTokenAddress Address of the token
     * @param child0 Address of the first child-bridge contract
     * @param child1 Address of the second child-bridge contract
     */
    function sendForkonomicTokensToChildren(
        address gasTokenAddress,
        address child0,
        address child1
    ) public {
        IForkonomicToken(gasTokenAddress).splitTokensIntoChildTokens(
            IERC20(gasTokenAddress).balanceOf(address(this))
        );
        (address forkonomicToken1, address forkonomicToken2) = IForkonomicToken(
            gasTokenAddress
        ).getChildren();
        IERC20(forkonomicToken1).transfer(
            child0,
            IERC20(forkonomicToken1).balanceOf(address(this))
        );
        IERC20(forkonomicToken2).transfer(
            child1,
            IERC20(forkonomicToken2).balanceOf(address(this))
        );
    }
}
