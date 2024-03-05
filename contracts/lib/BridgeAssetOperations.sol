// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;
import {PolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/inheritedMainContracts/PolygonZkEVMBridge.sol";
import {TokenWrapped} from "@RealityETH/zkevm-contracts/contracts/lib/TokenWrapped.sol";
import {ForkableBridge} from "../ForkableBridge.sol";
import {IForkonomicToken} from "../interfaces/IForkonomicToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

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
        bytes memory metadata = abi.encode(
            _safeName(token),
            _safeSymbol(token),
            _safeDecimals(token)
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
    // Helpers to safely get the metadata from a token, copied from here: https://github.com/0xPolygonHermez/zkevm-contracts/blob/d70266b8742672d59d4060019538d03fe0aac181/contracts/PolygonZkEVMBridge.sol#L800

    /**
     * @notice Provides a safe ERC20.symbol version which returns 'NO_SYMBOL' as fallback string
     * @param token The address of the ERC-20 token contract
     */
    function _safeSymbol(address token) internal view returns (string memory) {
        (bool success, bytes memory data) = address(token).staticcall(
            abi.encodeCall(IERC20MetadataUpgradeable.symbol, ())
        );
        return success ? _returnDataToString(data) : "NO_SYMBOL";
    }

    /**
     * @notice  Provides a safe ERC20.name version which returns 'NO_NAME' as fallback string.
     * @param token The address of the ERC-20 token contract.
     */
    function _safeName(address token) internal view returns (string memory) {
        (bool success, bytes memory data) = address(token).staticcall(
            abi.encodeCall(IERC20MetadataUpgradeable.name, ())
        );
        return success ? _returnDataToString(data) : "NO_NAME";
    }

    /**
     * @notice Provides a safe ERC20.decimals version which returns '18' as fallback value.
     * Note Tokens with (decimals > 255) are not supported
     * @param token The address of the ERC-20 token contract
     */
    function _safeDecimals(address token) internal view returns (uint8) {
        (bool success, bytes memory data) = address(token).staticcall(
            abi.encodeCall(IERC20MetadataUpgradeable.decimals, ())
        );
        return success && data.length == 32 ? abi.decode(data, (uint8)) : 18;
    }

    /**
     * @notice Function to convert returned data to string
     * returns 'NOT_VALID_ENCODING' as fallback value.
     * @param data returned data
     */
    function _returnDataToString(
        bytes memory data
    ) internal pure returns (string memory) {
        if (data.length >= 64) {
            return abi.decode(data, (string));
        } else if (data.length == 32) {
            // Since the strings on bytes32 are encoded left-right, check the first zero in the data
            uint256 nonZeroBytes;
            while (nonZeroBytes < 32 && data[nonZeroBytes] != 0) {
                nonZeroBytes++;
            }

            // If the first one is 0, we do not handle the encoding
            if (nonZeroBytes == 0) {
                return "NOT_VALID_ENCODING";
            }
            // Create a byte array with nonZeroBytes length
            bytes memory bytesArray = new bytes(nonZeroBytes);
            for (uint256 i = 0; i < nonZeroBytes; i++) {
                bytesArray[i] = data[i];
            }
            return string(bytesArray);
        } else {
            return "NOT_VALID_ENCODING";
        }
    }
}
