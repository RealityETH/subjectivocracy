// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

import {IForkingManager} from "./interfaces/IForkingManager.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {IPolygonZkEVM} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";

// NB We'd normally use the interface IForkableBridge here but it causes an error:
//   Error (5005): Linearization of inheritance graph impossible
import {ForkableBridge} from "./ForkableBridge.sol";
import {L2ChainInfo} from "./L2ChainInfo.sol";

contract L1GlobalRouter {

    function updateL2ChainInfo(ForkableBridge _bridge, address _l2ChainInfo) external {

        // Ask the bridge its forkmanager
        // TODO: ForkableStructure has this but IForkableStructure doesn't
        IForkingManager fm = IForkingManager(ForkableBridge(_bridge).forkmanager());
        // Ask the parent forkmanager which side this forkmanager is  
        IForkingManager parentFm = IForkingManager(fm.parentContract());
        uint8 forkResult = 0;
        if (address(parentFm) != address(0)) {
            (address child1, address child2) = fm.getChildren();
            if (child1 == address(fm)) {
                forkResult = 1;
            } else if (child2 == address(fm)) {
                forkResult = 2;
            } else {
                revert("Unexpected child address");
            }
        }

        uint64 chainId = IPolygonZkEVM(fm.zkEVM()).chainID();

        uint256 arbitrationFee = fm.arbitrationFee();

        (bool isL1, address disputeContract, bytes32 disputeContent) = fm.disputeData();

        // TODO: Can we put the disputeData in ForkingManager in a bytes32?
        // Fork results: 0 for the genesis, 1 for yes, 2 for no 
        bytes memory data = abi.encode(fm, arbitrationFee, isL1, disputeContract, disputeContent, forkResult);

        IPolygonZkEVMBridge(_bridge).bridgeMessage(
            uint32(chainId),
            _l2ChainInfo,
            false, // TODO: Work out if we need forceUpdateGlobalExitRoot
            data
        );
    }
    
}
