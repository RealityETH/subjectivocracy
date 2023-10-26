// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

import {IForkingManager} from "./interfaces/IForkingManager.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {IPolygonZkEVM} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";

// NB We'd normally use the interface IForkableBridge here but it causes an error:
//   Error (5005): Linearization of inheritance graph impossible
import {ForkableBridge} from "./ForkableBridge.sol";
import {L2ChainInfo} from "./L2ChainInfo.sol";

// Any L2 contract can call us over the bridge to get us to request a fork.
// We record the dispute they were forking over
contract L1GlobalForkRequester {

    address public caller;
    
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
      require(uint64(_originNetwork) == zkevm.chainID(), "Unexpected _originNetwork, this should not happen");
    
      // We also check in the opposite direction to make sure the ForkingManager thinks the bridge is its bridge
      require(address(fm.bridge()) == msg.sender, "ForkingManager disagrees with the bridge about who is whose bridge");

      // TODO: The whitepaper implies a whitelist about who is allowed to fork us.
      // Currently anybody can as long as they pay.
      // require(originAddress == l1Contract);

      // Assume the data contains the questionId and pass it directly to the forkmanager in the fork request
      IForkingManager.NewImplementations memory ni;
      // TODO: check what _originAddress should be
      IForkingManager.DisputeData memory dd = IForkingManager.DisputeData(_originAddress, _data);
      fm.initiateFork(dd, ni);

    }



}
