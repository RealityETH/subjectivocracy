// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {InitializeChain} from "../../development/contracts/mixin/InitializeChain.sol";

contract InitializeChainWrapper is InitializeChain {
    constructor() InitializeChain() {}

    function onlyChainUninitializedWrapper() public onlyChainUninitialized {}

    function onlyChainInitializedWrapper()
        public
        onlyChainInitialized
    {}
}
