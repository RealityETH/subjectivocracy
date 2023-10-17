// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

import {IForkingManager} from "./interfaces/IForkingManager.sol";
import {IForkableBridge} from "./interfaces/IForkableBridge.sol";
import {IAMB} from "./interfaces/IAMB.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {IL2Directory} from "./interfaces/IL2Directory.sol";


// TODO: Fix up the interaces and use IForkableBridge instead
import {ForkableBridge} from "./ForkableBridge.sol";

/*
    // Struct that holds an address pair used to store the new child contracts
    struct AddressPair {
        address one;
        address two;
    }

    // Struct containing the addresses of the new instances
    struct NewInstances {
        AddressPair forkingManager;
        AddressPair bridge;
        AddressPair zkEVM;
        AddressPair forkonomicToken;
        AddressPair globalExitRoot;
    }

    function bridgeMessage(
        uint32 destinationNetwork,
        address destinationAddress,
        bool forceUpdateGlobalExitRoot,
        bytes calldata metadata
    ) external payable;

*/

contract L1GlobalRouter {
    
    function updateL2ChainInfo(IForkableBridge _bridge, address _l2Directory) external {

        // Ask the bridge its forkmanager
        // TODO: ForkableStructure has this but IForkableStructure doesn't
        IForkingManager fm = IForkingManager(IForkableBridge(_bridge).forkmanager());
        // Ask the parent forkmanager which side this forkmanager is  
        IForkingManager parentFm = IForkingManager(fm.parentContract());
        uint8 forkResult = 0;
        if (parentFm != address(0)) {
            (address child1, address child2) = fm.getChildren();
            if (child1 == address(fm)) {
                forkResult = 1;
            } else if (child2 == address(fm)) {
                forkResult = 2;
            } else {
                revert("Unexpected child address");
            }
        }

        address l1Token = fm.forkonomicToken();

        // Fork results: 0 for the genesis, 1 for yes, 2 for no 
        bytes4 methodSelector = IL2Directory(_bridge).updateChainInfo.selector;
        bytes32 dispute; // TODO: Get this from somewhere
        bytes memory data = abi.encodeWithSelector(methodSelector, fm, l1Token, dispute, forkResult);

        IAMB(_bridge).requireToPassMessage(
            _l2Directory,
            data,
            0 // TODO: work out gas
        );

    }

    /*
    function forwardToForkManager(uint256 chainId, bytes data) onlyOwner {
        IForkingManager fm = 
        address bridge = fm.bridge();
        if (!fm.call.value(value)(data)) {
            throw;
        }
        Forwarded(destination, value, data);
    }}
    */

}
