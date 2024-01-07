// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

import {IForkingManager} from "./interfaces/IForkingManager.sol";
import {IForkableStructure} from "./interfaces/IForkableStructure.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {IPolygonZkEVM} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";

contract L1GlobalChainInfoPublisher {
    /// @dev Error thrown when the ancestor is not found
    error AncestorNotFound();
    /// @dev Error thrown when the child address is not expected
    error UnexpectedChildAddress();

    /// @notice Function to send the data about a fork to a contract on L2.
    /// @param _bridge The bridge to send the data through
    /// @param _l2ChainInfo The L2ChainInfo contract on L2 to send the data to
    /// @param _ancestorForkingManager The ForkingManager to send data about, if referring to a previous fork (unusual)
    /// @param _maxAncestors The number of forks back to look when looking for the _ancestorForkingManager
    /// @dev Normally someone would call this right after a fork, _ancestorForkingManager and _maxAncestors should only be used in wierd cases
    function updateL2ChainInfo(
        address _bridge,
        address _l2ChainInfo,
        address _ancestorForkingManager,
        uint256 _maxAncestors
    ) external {
        // Ask the bridge its forkmanager
        IForkingManager forkingManager = IForkingManager(
            IForkableStructure(_bridge).forkmanager()
        );

        // If we passed an _ancestorForkingManager, crawl up and find that as our ancestor and send data for that over the current bridge.
        // We will refuse to send data about a forkingManager that isn't an ancestor of the one used by the bridge.
        // Normally we won't need to do this because we'll update L2ChainInfo as soon as there's a fork
        // This is here just in case there's some weird availability issue and we couldn't send an update before the next fork.
        // NB If we keep forking every week forever you will eventually become unable to get the earliest before running out of gas
        if (_ancestorForkingManager != address(0)) {
            bool found = false;
            for (uint256 i = 0; i < _maxAncestors; i++) {
                forkingManager = IForkingManager(
                    forkingManager.parentContract()
                );
                if (address(forkingManager) == address(0)) {
                    break; // No more ancestors
                }
                if (_ancestorForkingManager == address(forkingManager)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                revert AncestorNotFound();
            }
        }

        // Dispute results will need to come from the parent ForkingManager
        IForkingManager parentForkingManager = IForkingManager(
            forkingManager.parentContract()
        );

        bool isL1;
        address disputeContract;
        bytes32 disputeContent;

        // Fork results: 0 for the genesis, 1 for yes, 2 for no
        uint8 forkResult = 0;

        // Find out whether we are the "yes" fork or the "no" fork
        if (address(parentForkingManager) != address(0)) {
            (address child1, address child2) = parentForkingManager
                .getChildren();
            if (child1 == address(forkingManager)) {
                forkResult = 1;
            } else if (child2 == address(forkingManager)) {
                forkResult = 2;
            } else {
                revert UnexpectedChildAddress();
            }
            (isL1, disputeContract, disputeContent) = forkingManager
                .disputeData();
        }

        uint256 arbitrationFee = forkingManager.arbitrationFee();
        address forkonomicToken = forkingManager.forkonomicToken();
        uint64 chainId = IPolygonZkEVM(forkingManager.zkEVM()).chainID();

        bytes memory data = abi.encode(
            chainId,
            forkonomicToken,
            arbitrationFee,
            isL1,
            disputeContract,
            disputeContent,
            forkResult
        );

        IPolygonZkEVMBridge(_bridge).bridgeMessage(
            uint32(1),
            _l2ChainInfo,
            true,
            data
        );
    }
}
