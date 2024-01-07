// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

/* 
   Contract to proxy a fork request from the bridge to its ForkingManager
   Any L2 contract can call this contract over the bridge to request a fork.
   The disputes causing a fork are recorded in this contract
*/

import {IForkingManager} from "./interfaces/IForkingManager.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {IPolygonZkEVM} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";
import {IForkonomicToken} from "./interfaces/IForkonomicToken.sol";
import {IForkableBridge} from "./interfaces/IForkableBridge.sol";
import {IBridgeMessageReceiver} from "@RealityETH/zkevm-contracts/contracts/interfaces/IBridgeMessageReceiver.sol";

import {MoneyBox} from "./mixin/MoneyBox.sol";
import {CalculateMoneyBoxAddress} from "./lib/CalculateMoneyBoxAddress.sol";

contract L1GlobalForkRequester {
    /// @dev Error thrown when the transfer out of the moneyBox is unsuccessful
    error UnsuccessfulTransfer();
    /// @dev Error thrown when the migration has already started
    error MigrationAlreadyStarted();
    /// @dev Error thrown when the token has not yet been forked
    error TokenNotYetForked();
    /// @dev Error thrown when there is nothing to return
    error NothingToReturn();
    /// @dev Error thrown when the bridge and the forkmanager are not related
    error BridgeForkManagerMismatch();
    /// @dev Error thrown when the forkonomic token and the forkmanager are not related
    error ForkonomicTokenMisMatch();


    struct FailedForkRequest {
        uint256 amount;
        uint256 amountMigratedYes;
        uint256 amountMigratedNo;
    }

    // Token => Beneficiary => ID => FailedForkRequest
    mapping(address => mapping(address => mapping(bytes32 => FailedForkRequest)))
        public failedRequests;

    /**
     * @dev This function can be called by anyone to to take the money out of the moneybox and initiated the fork.
     * Normally this would only happen if the L2 contract send a payment but in theory someone else could fund it directly on L1.
     * @param token The address of the forkonomic token used to pay the forking fee
     * @param beneficiary The receiver of the tokens, if the call does not go through. Normally the "beneficiary" would be the sender on L2.
     * @param requestId The questionId of the dispute
     */
    function handlePayment(
        address token,
        address beneficiary,
        bytes32 requestId
    ) external {
        bytes32 salt = keccak256(abi.encodePacked(beneficiary, requestId));

        // Check the MoneyBox has funds
        address moneyBox = CalculateMoneyBoxAddress._calculateMoneyBoxAddress(
            address(this),
            salt,
            token
        );

        // If for some reason we've already got part of a payment, include it.
        uint256 initialBalance = failedRequests[token][beneficiary][requestId]
            .amount;

        uint256 transferredBalance = initialBalance +
            IForkonomicToken(token).balanceOf(moneyBox);

        if (moneyBox.code.length == 0) {
            new MoneyBox{salt: salt}(token);
        }
        if (
            !IForkonomicToken(token).transferFrom(
                moneyBox,
                address(this),
                transferredBalance
            )
        ) {
            revert UnsuccessfulTransfer();
        }

        // If the token is already being or has already been forked, record the request as failed.
        // Somebody can split the token after the fork, then send the failure message and the funds back on both the child forks.
        IForkingManager forkingManager = IForkingManager(
            IForkonomicToken(token).forkmanager()
        );

        if (
            transferredBalance >= forkingManager.arbitrationFee() &&
            !forkingManager.isForkingInitiated()
        ) {
            if (initialBalance > 0) {
                delete (failedRequests[token][beneficiary][requestId]);
            }

            IForkonomicToken(token).approve(
                address(forkingManager),
                transferredBalance
            );

            // Assume the data contains the questionId and pass it directly to the forkmanager in the fork request
            IForkingManager.DisputeData memory disputeData = IForkingManager
                .DisputeData(false, beneficiary, requestId);
            forkingManager.initiateFork(disputeData);
        } else {
            // Store the request so we can return the tokens across the bridge
            // If the fork has already happened we may have to split them first and do this twice.
            failedRequests[token][beneficiary][requestId]
                .amount += transferredBalance;
        }
    }

    /**
     * @dev This function can be called by anyone to split the tokens into the child tokens. This is required
     * in case another fork is executed before the fork request is processed.
     * @param token The address of the forkonomic token used to pay the forking fee
     * @param requester The receiver of the tokens, if the call does not go through. Normally the "beneficiary" would be the sender on L2.
     * @param requestId The questionId of the dispute
     * @param doYesToken Whether to split the tokens into the first child or the second child
     * @param useChildTokenAllowance Whether to use the child token allowance or burn the tokens
     */
    function splitTokensIntoChildTokens(
        address token,
        address requester,
        bytes32 requestId,
        bool doYesToken,
        bool useChildTokenAllowance
    ) external {
        uint256 amount = failedRequests[token][requester][requestId].amount;

        // You need to call registerPayment before you call this.
        if (amount == 0) {
            revert NothingToReturn();
        }

        (address yesToken, address noToken) = IForkonomicToken(token)
            .getChildren();
        if (doYesToken) {
            if (yesToken == address(0)) {
                revert TokenNotYetForked();
            }
        } else {
            if (noToken == address(0)) {
                revert TokenNotYetForked();
            }
        }

        IForkonomicToken(token).splitTokenAndMintOneChild(
            amount,
            doYesToken,
            useChildTokenAllowance
        );

        if (doYesToken) {
            uint newAmountToMigrate = amount -
                failedRequests[token][requester][requestId].amountMigratedYes;
            failedRequests[yesToken][requester][requestId]
                .amount += newAmountToMigrate;
            failedRequests[token][requester][requestId]
                .amountMigratedYes += newAmountToMigrate;
        } else {
            uint256 newAmountToMigrate = amount -
                failedRequests[token][requester][requestId].amountMigratedNo;
            failedRequests[noToken][requester][requestId]
                .amount += newAmountToMigrate;
            failedRequests[token][requester][requestId]
                .amountMigratedNo += newAmountToMigrate;
        }
    }

    /**
     * @dev This function can be called by anyone to return the tokens across the bridge.
     * @param token The address of the forkonomic token used to pay the forking fee
     * @param beneficiary The receiver of the tokens, if the call does not go through. Normally the "beneficiary" would be the sender on L2.
     * @param requestId The questionId of the dispute
     */
    function returnTokens(
        address token,
        address beneficiary,
        bytes32 requestId
    ) external {
        IForkingManager forkingManager = IForkingManager(
            IForkonomicToken(token).forkmanager()
        );
        IForkableBridge bridge = IForkableBridge(forkingManager.bridge());
        if (
            failedRequests[token][beneficiary][requestId].amountMigratedNo !=
            0 ||
            failedRequests[token][beneficiary][requestId].amountMigratedYes != 0
        ) {
            revert MigrationAlreadyStarted();
        }

        // Check the relations in the other direction to make sure we don't lie to the bridge somehow
        if (address(bridge.forkmanager()) != address(forkingManager)) {
            revert BridgeForkManagerMismatch();
        }
        if (address(forkingManager.forkonomicToken()) != token) {
            revert ForkonomicTokenMisMatch();
        }

        uint256 amount = failedRequests[token][beneficiary][requestId].amount;

        if (amount == 0) {
            revert NothingToReturn();
        }
        IForkonomicToken(token).approve(address(bridge), amount);

        bytes memory permitData;
        bridge.bridgeAsset(
            uint32(1),
            beneficiary,
            amount,
            token,
            true,
            permitData
        );

        // TODO: It might be useful to send information about the failure eg fork timestamp
        bytes memory data = bytes.concat(requestId);
        bridge.bridgeMessage(uint32(1), beneficiary, true, data);

        delete (failedRequests[token][beneficiary][requestId]);
    }
}
