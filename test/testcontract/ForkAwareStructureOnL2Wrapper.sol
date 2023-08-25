// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {ForkAwareStructureOnL2} from "../../development/contracts/mixin/ForkAwareStructureOnL2.sol";

contract ForkAwareStructureOnL2Wrapper is ForkAwareStructureOnL2 {
    constructor() ForkAwareStructureOnL2() {}

    function onlyFirstTxAfterForkWrapper() public onlyFirstTxAfterFork {}

    function everyButFirstTxAfterForkWrapper()
        public
        everyButFirstTxAfterFork
    {}
}
