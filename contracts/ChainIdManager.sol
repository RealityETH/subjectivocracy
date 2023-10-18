// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {Owned} from "./mixin/Owned.sol";

contract ChainIdManager is Owned{

    // Counter for the number of used Chain IDs
    uint256 public usedChainIdCounter = 0;
    // Counter for the number of Chain IDs
    uint256 public chainIdCounter = 0;
    mapping (uint256 => uint256) public usableChainIds;

    constructor() Owned(){
    }

    /**
     * @dev Adds a Chain ID
     * @param chainId The Chain ID to add
     */
    function addChainId(uint256 chainId) public onlyOwner() {
        usableChainIds[chainIdCounter] = chainId;
        chainIdCounter++;
    }

    /**
     * @dev Adds multiple Chain IDs
     * @param chainIds The Chain IDs to add
     */
    function addChainIds(uint256[] memory chainIds) public onlyOwner() {
        for (uint256 i = 0; i < chainIds.length; i++) {
            addChainId(chainIds[i]);
        }
    }

    /**
     * @dev Returns the next usable Chain ID
     * @return chainId The next usable Chain ID
     */
    function getNextUsableChainId() public returns (uint256 chainId) {
        // Todo: Add a ddos protection: Probably charging gas. But for now,
        // the owner can counter ddos attacks by readding unused chainIds
        chainId = usableChainIds[usedChainIdCounter];
        require(chainId != 0, "No usable Chain ID available");
        usedChainIdCounter++;
    }

}