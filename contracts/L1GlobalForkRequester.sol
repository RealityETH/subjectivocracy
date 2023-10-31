// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

/* 
   Contract to proxy a fork request from the bridge to its ForkingManager
   Any L2 contract can call us over the bridge to get us to request a fork.
   We record the dispute they were forking over
*/

// TODO: An alternative would be to look up the ForkingManager direct from L2ChainInfo and call it directly.
// TODO: We could use this to manage the dispute data, in which case we could gate initiateFork() to only be callable by us.
// TODO: The whitepaper implies a whitelist about who is allowed to fork us. Currently anybody can as long as they pay.

import {IForkingManager} from "./interfaces/IForkingManager.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {IPolygonZkEVM} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";

// NB We'd normally use the interface IForkableBridge here but it causes an error:
//  Error (5005): Linearization of inheritance graph impossible
import {ForkableBridge} from "./ForkableBridge.sol";

contract L1GlobalForkRequester {

    // Any bridge (or any contract pretending to be a bridge) can call this.
    // We'll look up its ForkingManager and ask it for a fork.
    // TODO: It might make more sense if this contract requested the chain ID then kept a record of it.
    // ...then the ForkingManager would be locked to only fork based on our request.

    function onMessageReceived(address _originAddress, uint32 _originNetwork, bytes memory _data) external payable {

      ForkableBridge bridge = ForkableBridge(msg.sender);
      IForkingManager fm = IForkingManager(bridge.forkmanager());

      // The chain ID should always be the chain ID expected by the ForkingManager.
      // It shouldn't be possible for it to be anything else but we'll check it anyhow.
      IPolygonZkEVM zkevm = IPolygonZkEVM(fm.zkEVM());
      require(uint64(_originNetwork) == zkevm.chainID(), "Bad _originNetwork, WTF");
    
      // We also check in the opposite direction to make sure the ForkingManager thinks the bridge is its bridge
      require(address(fm.bridge()) == msg.sender, "Bridge mismatch, WTF");

      // Assume the data contains the questionId and pass it directly to the forkmanager in the fork request
      IForkingManager.NewImplementations memory ni;
      // TODO: check what _originAddress should be
      IForkingManager.DisputeData memory dd = IForkingManager.DisputeData(false, _originAddress, bytes32(_data));
      fm.initiateFork(dd, ni);

    }

}
