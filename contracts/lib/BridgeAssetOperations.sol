// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
import {PolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/inheritedMainContracts/PolygonZkEVMBridge.sol";
import {TokenWrapped} from "@RealityETH/zkevm-contracts/contracts/lib/TokenWrapped.sol";
import {ForkableBridge} from "../ForkableBridge.sol";
import {IForkonomicToken} from "../interfaces/IForkonomicToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

library BridgeAssetOperations {
    // @dev Error thrown when forkable token is intended to be used, but it is not forkable
    error TokenNotForkable();
    // @dev Error thrown when token is not issued before
    error TokenNotIssuedBefore();

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
        if (tokenInfo.originNetwork == 0) {
            revert TokenNotForkable();
        }
        if (tokenInfo.originTokenAddress == address(0)) {
            revert TokenNotIssuedBefore();
        }
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
     * @notice Function to create child tokens after splitting operation
     * @param token Address of the token
     * @param amount Amount of tokens to transfer
     * @param tokenInfo Information about the token
     * @param child Address of the first child-bridge contract
     */
    function createChildToken(
        address token,
        uint256 amount,
        PolygonZkEVMBridge.TokenInformation memory tokenInfo,
        address child
    ) public {
        if (tokenInfo.originNetwork == 0) {
            revert TokenNotForkable();
        }
        (bool successNameCall, bytes memory name) = token.staticcall(
            /// encoding the function signature of N
            abi.encodeWithSignature("name()")
        );
        if (!successNameCall) {
            name = abi.encode("unknown-", token);
        }
        (bool successSymbolCall, bytes memory symbol) = token.staticcall(
            abi.encodeWithSignature("symbol()")
        );
        if (!successSymbolCall) {
            symbol = abi.encode("UNKNOWN");
        }
        (bool successDecimalsCall, bytes memory decimals) = token.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        if (!successDecimalsCall) {
            // setting the standard of 18 decimals might be wrong, but its better than locking the tokens for-ever in the forked bridge contract.
            // we could also during deposits enforce that decimals() is readable
            decimals = abi.encode("18");
        }
        bytes memory metadata = abi.encode(
            abi.decode(name, (string)),
            abi.decode(symbol, (string)),
            abi.decode(decimals, (uint8))
        );
        ForkableBridge(child).mintForkableToken(
            tokenInfo.originTokenAddress,
            tokenInfo.originNetwork,
            amount,
            metadata,
            msg.sender
        );
    }

    // @inheritdoc IForkableBridge
    function splitTokenIntoChildToken(
        address token,
        uint256 amount,
        address child1,
        address child2,
        PolygonZkEVMBridge.TokenInformation memory tokenInfo
    ) public {
        TokenWrapped(token).burn(msg.sender, amount);
        createChildToken(token, amount, tokenInfo, child1);
        if (child2 != address(0)) {
            createChildToken(token, amount, tokenInfo, child2);
        }
    }

    /**
     * @notice Function to send tokens into children-bridge contract by the admin
     * @param gasTokenAddress Address of the token
     * @param child Address of the first child-bridge contract
     * @param useFirstChild Boolean to indicate which child to send tokens to
     */
    function sendForkonomicTokensToChild(
        address gasTokenAddress,
        uint256 amount,
        address child,
        bool useFirstChild,
        bool useChildTokenAllowance
    ) public {
        IForkonomicToken(gasTokenAddress).splitTokenAndMintOneChild(
            amount,
            useFirstChild,
            useChildTokenAllowance
        );
        (address forkonomicToken1, address forkonomicToken2) = IForkonomicToken(
            gasTokenAddress
        ).getChildren();
        if (useFirstChild) {
            IERC20(forkonomicToken1).transfer(child, amount);
        } else {
            IERC20(forkonomicToken2).transfer(child, amount);
        }
    }
}
