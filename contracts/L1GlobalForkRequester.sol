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

// NB We'd normally use the interface IForkableBridge here but it causes an error:
//  Error (5005): Linearization of inheritance graph impossible
import {ForkableBridge} from "./ForkableBridge.sol";

// TODO: Is this the right IERC20 interface? We have lots.
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IBridgeMessageReceiver} from "@RealityETH/zkevm-contracts/contracts/interfaces/IBridgeMessageReceiver.sol";

contract L1GlobalForkRequester is IBridgeMessageReceiver {

    // Any bridge (or any contract pretending to be a bridge) can call this.
    // We'll look up its ForkingManager and ask it for a fork.
    // TODO: It might make more sense if this contract requested the chain ID then kept a record of it.
    // ...then the ForkingManager would be locked to only fork based on our request.

    // Presumably this automatically has the tokens in its balance at this point, although we still need to test this.
    function onMessageReceived(address _originAddress, uint32 _originNetwork, bytes memory _data) external payable {

      ForkableBridge bridge = ForkableBridge(msg.sender);
      IForkingManager forkingManager = IForkingManager(bridge.forkmanager());

      // The chain ID should always be the chain ID expected by the ForkingManager.
      // It shouldn't be possible for it to be anything else but we'll check it anyhow.
      IPolygonZkEVM zkevm = IPolygonZkEVM(forkingManager.zkEVM());
      require(uint64(_originNetwork) == zkevm.chainID(), "Bad _originNetwork, WTF");
    
      // We also check in the opposite direction to make sure the ForkingManager thinks the bridge is its bridge
      require(address(forkingManager.bridge()) == msg.sender, "Bridge mismatch, WTF");

      // TODO:
      // 1) Work out what happens if this reverts.
      // 2) Work out how the fee is handled

      uint256 fee = forkingManager.arbitrationFee();
      IERC20 token = IERC20(forkingManager.forkonomicToken());

      bool isFailed = false;

      // Fee must be supplied
      // TODO: Check how the bridge works. This doesn't require a separate call to claim the asset does it?
      //       If so, do we need to revert here so it can be called again?
      if (!isFailed && token.balanceOf(address(this)) <= fee) {
        isFailed = true;
      }
      // Shouldn't fail but who knows
      if (!isFailed && !token.approve(address(forkingManager), fee)) {
        isFailed = true;
      }
 
      // TODO: Add this to ForkingManager
      // if (!isFailed && !forkingManager.canForkNow()) {
      //   isFailed = true;
      // }
    
      // TODO: Do we need to check anything about _originNetwork? 
      if (isFailed) {
        _handleFail(_originAddress, _originNetwork, _data);
      }

      // Assume the data contains the questionId and pass it directly to the forkmanager in the fork request
      IForkingManager.NewImplementations memory newImplementations;
      IForkingManager.DisputeData memory disputeData = IForkingManager.DisputeData(false, _originAddress, bytes32(_data));

      // This shouldn't be able to revert
      forkingManager.initiateFork(disputeData, newImplementations);


    }

    // If this fails, send the funds back across the bridge to the contract that requested it.
    function _handleFail(address _originAddress, uint32 _originNetwork, bytes memory _data) internal {
        
        ForkableBridge bridge = ForkableBridge(msg.sender);
        bridge.bridgeMessage(
            _originNetwork,
            _originAddress,
            false, // TODO: Work out if we need forceUpdateGlobalExitRoot
            _data
        );

    }

}
