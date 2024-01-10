// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

// Currently, this contract is not used. Ed came up with its own isChainUpToDate() modifier.
//  Maybe we have to delete it.

/** This contract can be inherited form any other contrac that needs to be aware of Forks.
This contract uses the fact that after a fork the chainId changes and thereby detects forks*/

contract InitializeChain {
    /// @dev Error thrown when contract is expected to be called on a new fork
    error NotOnNewFork();
    /// @dev Error thrown when contract is expected not to be called on a new fork
    error OnNewFork();
    uint256 public chainId;

    modifier onlyChainUninitialized() {
        if (chainId == block.chainid) {
            revert NotOnNewFork();
        }
        _;
        chainId = block.chainid;
    }

    modifier onlyChainInitialized() {
        if (chainId != block.chainid) {
            revert OnNewFork();
        }
        _;
    }

    constructor() {
        chainId = block.chainid;
    }
}
