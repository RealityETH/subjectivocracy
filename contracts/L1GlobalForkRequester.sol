// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

/* 
   Contract to proxy a fork request from the bridge to its ForkingManager
   Any L2 contract can call us over the bridge to get us to request a fork.
   We record the dispute they were forking over
*/

import {IForkingManager} from "./interfaces/IForkingManager.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {IPolygonZkEVM} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";
import {IForkonomicToken} from "./interfaces/IForkonomicToken.sol";

// NB We'd normally use the interface IForkableBridge here but it causes an error:
//  Error (5005): Linearization of inheritance graph impossible
import {ForkableBridge} from "./ForkableBridge.sol";

import {IBridgeMessageReceiver} from "@RealityETH/zkevm-contracts/contracts/interfaces/IBridgeMessageReceiver.sol";

import {MoneyBox} from "./mixin/MoneyBox.sol";
import {CalculateMoneyBoxAddress} from "./lib/CalculateMoneyBoxAddress.sol";

contract L1GlobalForkRequester {
    struct FailedForkRequest {
        uint256 amount;
        uint256 amountMigratedYes;
        uint256 amountMigratedNo;
    }
    // Token => Beneficiary => ID => FailedForkRequest
    mapping(address => mapping(address => mapping(bytes32 => FailedForkRequest)))
        public failedRequests;

    // Anybody can say, "Hey, you got a payment for this fork to happen"
    // Normally this would only happen if the L2 contract send a payment but in theory someone else could fund it directly on L1.
    function handlePayment(
        address token,
        address beneficiary,
        bytes32 requestId
    ) external {
        // Normally the "beneficiary" would be the sender on L2.
        // But if some other kind person sent funds to this address we would still send it back to the beneficiary.

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
        require(
            IForkonomicToken(token).transferFrom(
                moneyBox,
                address(this),
                transferredBalance
            ),
            "Preparing payment failed"
        );

        // If the token is already being or has already been forked, record the request as failed.
        // Somebody can split the token after the fork, then send the failure message and the funds back on both the child forks.
        // TODO: Replace this with an isForked() method in ForkingStructure.sol?

        IForkingManager forkingManager = IForkingManager(
            IForkonomicToken(token).forkmanager()
        );

        bool isForkGuaranteedNotToRevert = true;
        if (transferredBalance < forkingManager.arbitrationFee()) {
            isForkGuaranteedNotToRevert = false;
        }
        if (!forkingManager.canFork()) {
            isForkGuaranteedNotToRevert = false;
        }

        if (isForkGuaranteedNotToRevert) {
            if (initialBalance > 0) {
                delete (failedRequests[token][beneficiary][requestId]);
            }

            IForkonomicToken(token).approve(
                address(forkingManager),
                transferredBalance
            );

            // Assume the data contains the questionId and pass it directly to the forkmanager in the fork request
            IForkingManager.NewImplementations memory newImplementations;
            IForkingManager.DisputeData memory disputeData = IForkingManager
                .DisputeData(false, beneficiary, requestId);
            forkingManager.initiateFork(disputeData, newImplementations);
        } else {
            // Store the request so we can return the tokens across the bridge
            // If the fork has already happened we may have to split them first and do this twice.
            failedRequests[token][beneficiary][requestId]
                .amount = transferredBalance;
        }
    }

    // If something was queued after a fork had happened, we need to be able to return then to both bridges
    function splitTokensIntoChildTokens(
        address token,
        address requester,
        bytes32 requestId
    ) external {
        //function splitTokensIntoChildTokens(address token, address requester, bytes32 requestId, bool doYesToken, bool doNoToken) external {}
        // TODO: We need to update ForkonomicToken to handle each side separately in case one bridge reverts maliciously.
        // Then handle only one side being requested, or only one side being left
        uint256 amount = failedRequests[token][requester][requestId].amount;

        // You need to call registerPayment before you call this.
        require(amount > 0, "Nothing to split");

        (address yesToken, address noToken) = IForkonomicToken(token)
            .getChildren();
        require(
            yesToken != address(0) && noToken != address(0),
            "Token not forked"
        );

        // Current version only has a single function so we have to migrate both sides
        IForkonomicToken(token).splitTokensIntoChildTokens(amount);
        failedRequests[yesToken][requester][requestId].amount += amount;
        failedRequests[noToken][requester][requestId].amount += amount;
        delete (failedRequests[token][requester][requestId]);

        /*
        // Probably need something like:

        uint256 amountRemainingY = amount - failedRequests[token][requester][requestId].amountMigratedYes;
        uint256 amountRemainingN = amount - failedRequests[token][requester][requestId].amountMigratedNo;

        if (doYesToken) {
            require(amountRemainingY > 0, "Nothing to migrate for Y");
            token.splitTokensIntoChildTokens(amountRemainingY, 1);
            amountRemainingY = 0;
        }

        if (doNoToken) {
            require(amountMigratedNo > 0, "Nothing to migrate for N");
            token.splitTokensIntoChildTokens(amountMigratedNo, 0);
            amountRemainingN = 0;
        }

        if (amountRemainingY == 0 && amountRemainingN == 0) {
            delete(failedRequests[token][requester][requestId]);
        } else {
            failedRequests[token][requester][requestId].amountRemainingY = amountRemainingY;
            failedRequests[token][requester][requestId].amountRemainingN = amountRemainingN;
        }
        */
    }

    function returnTokens(
        address token,
        address requester,
        bytes32 requestId
    ) external {
        IForkingManager forkingManager = IForkingManager(
            IForkonomicToken(token).forkmanager()
        );
        ForkableBridge bridge = ForkableBridge(forkingManager.bridge());

        // Check the relations in the other direction to make sure we don't lie to the bridge somehow
        require(
            address(bridge.forkmanager()) == address(forkingManager),
            "Bridge/manager mismatch, WTF"
        );
        require(
            address(forkingManager.forkonomicToken()) == token,
            "Token/manager mismatch, WTF"
        );

        uint256 amount = failedRequests[token][requester][requestId].amount;

        require(amount > 0, "Nothing to return");
        IForkonomicToken(token).approve(address(bridge), amount);

        bytes memory permitData;
        bridge.bridgeAsset(
            uint32(1),
            requester,
            amount,
            token, // TODO: Should this be address(0)?
            true,
            permitData
        );

        // TODO: It might be useful to send information about the failure eg fork timestamp
        bytes memory data = bytes.concat(requestId);
        bridge.bridgeMessage(uint32(1), requester, true, data);

        delete (failedRequests[token][requester][requestId]);
    }
}
