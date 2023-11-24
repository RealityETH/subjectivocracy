// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

import {IForkingManager} from "./interfaces/IForkingManager.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {IPolygonZkEVM} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";

// NB We'd normally use the interface IForkableBridge here but it causes an error:
//   Error (5005): Linearization of inheritance graph impossible
import {ForkableBridge} from "./ForkableBridge.sol";
import {L2ChainInfo} from "./L2ChainInfo.sol";

contract L1GlobalChainInfoPublisher {

    function updateL2ChainInfo(address _bridge, address _l2ChainInfo, address _ancestorForkingManager, uint256 _maxAncestors) external {

        // Ask the bridge its forkmanager
        // TODO: ForkableStructure has this but IForkableStructure doesn't
        IForkingManager forkingManager = IForkingManager(ForkableBridge(_bridge).forkmanager());

        // If we passed an _ancestorForkingManager, crawl up and find that as our ancestor and send data for that over the current bridge.
        // Normally we won't need to do this because we'll update L2ChainInfo as soon as there's a fork
        // This is here just in case there's some weird availability issue and we couldn't send an update before the next fork.
        // NB If we keep forking every week forever you will eventually become unable to get the earliest before running out of gas
        if (_ancestorForkingManager != address(0)) {
            bool found = false;
            for(uint256 i = 0; i < _maxAncestors; i++) {
                forkingManager = IForkingManager(forkingManager.parentContract());
                require(address(forkingManager) != address(0), "Ancestor not found");
                if (_ancestorForkingManager == address(forkingManager)) {
                    found = true;
                    break;
                }
            }
            require(found, "Ancestor not found");
        }

        // Ask the parent forkmanager which side this forkmanager is  
        IForkingManager parentForkingManager = IForkingManager(forkingManager.parentContract());
        uint8 forkResult = 0;
        if (address(parentForkingManager) != address(0)) {
            (address child1, address child2) = parentForkingManager.getChildren();
            if (child1 == address(forkingManager)) {
                forkResult = 1;
            } else if (child2 == address(forkingManager)) {
                forkResult = 2;
            } else {
                revert("Unexpected child address");
            }
        }

        uint256 arbitrationFee = forkingManager.arbitrationFee();
        address forkonomicToken = forkingManager.forkonomicToken();

        uint64 chainId = IPolygonZkEVM(forkingManager.zkEVM()).chainID();

        (bool isL1, address disputeContract, bytes32 disputeContent) = forkingManager.disputeData();

        // TODO: Can we put the disputeData in ForkingManager in a bytes32?
        // Fork results: 0 for the genesis, 1 for yes, 2 for no 
        bytes memory data = abi.encode(chainId, forkonomicToken, arbitrationFee, isL1, disputeContract, disputeContent, forkResult);

        IPolygonZkEVMBridge(_bridge).bridgeMessage(
            uint32(1),
            _l2ChainInfo,
            true,
            data
        );
    }
    
}
