// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

/* 
   Contract to proxy a fork request from the bridge to its ForkingManager
   Any L2 contract can call us over the bridge to get us to request a fork.
   We record the dispute they were forking over
*/

// TODO: An alternative would be to look up the ForkingManager on L2ChainInfo and call it directly.
// TODO: We could use this to manage the dispute data, in which case we could gate initiateFork() to only be callable by us.
// TODO: The whitepaper implies a whitelist about who is allowed to fork us. Currently anybody can as long as they pay.

import {IForkingManager} from "./interfaces/IForkingManager.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {IPolygonZkEVM} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";
import {IForkonomicToken} from "./interfaces/IForkonomicToken.sol";

// NB We'd normally use the interface IForkableBridge here but it causes an error:
//  Error (5005): Linearization of inheritance graph impossible
import {ForkableBridge} from "./ForkableBridge.sol";

import {IBridgeMessageReceiver} from "@RealityETH/zkevm-contracts/contracts/interfaces/IBridgeMessageReceiver.sol";

import {MoneyBox} from "./MoneyBox.sol";
import {MoneyBoxUser} from "./MoneyBoxUser.sol";

contract L1GlobalForkRequester is IBridgeMessageReceiver, MoneyBoxUser {

    struct FailedForkRequest {
        uint256 amount;
        bool migratedY;
        bool migratedN;
    }
    // Token => Requester => ID => FailedForkRequest 
    mapping(address=>mapping(address=>mapping(bytes32=>FailedForkRequest))) public failedRequests;

    // Any bridge (or any contract pretending to be a bridge) can call this.
    // We'll look up its ForkingManager and ask it for a fork.
    // TODO: It might make more sense if this contract requested the chain ID then kept a record of it.
    // ...then the ForkingManager would be locked to only fork based on our request.

    function onMessageReceived(address _originAddress, uint32 _originNetwork, bytes memory _data) external payable {

        ForkableBridge bridge = ForkableBridge(msg.sender);
        IForkingManager forkingManager = IForkingManager(bridge.forkmanager());
        IForkonomicToken forkonomicToken = IForkonomicToken(forkingManager.forkonomicToken());

        // The chain ID should always be the chain ID expected by the ForkingManager.
        // It shouldn't be possible for it to be anything else but we'll check it anyhow.
        IPolygonZkEVM zkevm = IPolygonZkEVM(forkingManager.zkEVM());
        require(uint64(_originNetwork) == zkevm.chainID(), "Bad _originNetwork, WTF");

        // We also check in the opposite direction to make sure the ForkingManager thinks the bridge is its bridge etc
        require(address(forkingManager.bridge()) == msg.sender, "Bridge mismatch, WTF");
        require(address(forkonomicToken.forkmanager()) == address(forkingManager), "Token/manager mismatch, WTF");

        // TODO: Check if we should have anything else identifying the transfer
        bytes32 salt = keccak256(abi.encodePacked(msg.sender));
        address moneyBox = _calculateMoneyBoxAddress(address(this), salt, address(forkonomicToken));
        uint256 transferredBalance = forkonomicToken.balanceOf(moneyBox);

        if (moneyBox.code.length == 0) {
            new MoneyBox{salt: salt}(address(forkonomicToken));
        }
        require(forkonomicToken.transferFrom(moneyBox, address(this), transferredBalance), "Preparing payment failed");

        bool canFork = false; // TODO: Get this from the ForkingManager

        if (canFork) {
            forkonomicToken.approve(address(forkingManager), transferredBalance);

            // Assume the data contains the questionId and pass it directly to the forkmanager in the fork request
            IForkingManager.NewImplementations memory newImplementations;
            IForkingManager.DisputeData memory disputeData = IForkingManager.DisputeData(false, _originAddress, bytes32(_data));
            forkingManager.initiateFork(disputeData, newImplementations);

        } else {

            // Store the request so we can return the tokens across the bridge
            // If the fork has already happened we may have to split them first and do this twice.
            failedRequests[address(forkonomicToken)][msg.sender][salt] = FailedForkRequest(transferredBalance, false, false);

        }

    }

    // If something was queued after a fork had happened, we need to be able to return then to both bridges
    function splitTokensIntoChildTokens(address token, address requester, bytes32 requestId) external {
    //function splitTokensIntoChildTokens(address token, address requester, bytes32 requestId, bool doYesToken, bool doNoToken) external {}
        // TODO: We need to update ForkonomicToken to handle each side separately in case one bridge reverts maliciously.
        // Then handle only one side being requested, or only one side being left
        uint256 amount = failedRequests[token][requester][requestId].amount;
        require(amount > 0, "Nothing to split");

        (address yesToken, address noToken)  = IForkonomicToken(token).getChildren();
        require(yesToken != address(0) && noToken != address(0), "Token not forked");

        // Current version with a single function
        IForkonomicToken(token).splitTokensIntoChildTokens(amount);
        failedRequests[yesToken][requester][requestId] = FailedForkRequest(amount, false, false);
        failedRequests[noToken][requester][requestId] = FailedForkRequest(amount, false, false);
        delete(failedRequests[token][requester][requestId]);

        /*
        // Should probably be something like:

        bool migratedY = failedRequests[token][requester][requestId].migratedY;
        bool migratedN = failedRequests[token][requester][requestId].migratedN;

        if (doYesToken) {
            require(!migratedY, "Already migrated Y");
            token.splitTokensIntoChildTokens(uint256 amount, 1);
            migratedY = true;
        }

        if (doNoToken) {
            require(!migratedN, "Already migrated N");
            token.splitTokensIntoChildTokens(uint256 amount, 0);
            migratedN = true;
        }

        if (migratedY && migratedN) {
            delete(failedRequests[token][requester][requestId]);
        } else {
            failedRequests[token][requester][requestId] = migratedY;
            failedRequests[token][requester][requestId] = migratedN;
        }
        */
    }

    function returnTokens(address token, address requester, bytes32 requestId) external {

        IForkingManager forkingManager = IForkingManager(IForkonomicToken(token).forkmanager());
        ForkableBridge bridge = ForkableBridge(forkingManager.bridge());
        IPolygonZkEVM zkevm = IPolygonZkEVM(forkingManager.zkEVM());

        // Check the relations in the other direction to make sure we don't lie to the bridge somehow
        require(address(bridge.forkmanager()) == address(forkingManager), "Bridge/manager mismatch, WTF");
        require(address(forkingManager.forkonomicToken()) == token, "Token/manager mismatch, WTF");

        uint256 amount = failedRequests[token][requester][requestId].amount;

        require(amount > 0, "Nothing to return");
        IForkonomicToken(token).approve(address(bridge), amount);

        uint64 chainId = zkevm.chainID();

        bytes memory permitData;
        bridge.bridgeAsset(
            uint32(chainId),
            requester,
            amount,
            token, // TODO: Should this be address(0)?
            true,
            permitData
        );

        // TODO: It might be useful to send information about the failure eg fork timestamp
        bytes memory data = bytes.concat(requestId);
        bridge.bridgeMessage(
            uint32(chainId),
            requester,
            true,
            data
        );

        delete(failedRequests[token][requester][requestId]);

    }

}
