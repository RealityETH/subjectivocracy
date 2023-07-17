pragma solidity ^0.8.17;

import {ForkableUUPS} from "../../development/contracts/mixin/ForkableUUPS.sol";

contract ForkableUUPSWrapper is ForkableUUPS {
    function initialize(
        address _forkmanager,
        address _parentContract,
        address _updater
    ) public override initializer {
        ForkableUUPS.initialize(_forkmanager, _parentContract, _updater);
    }

    function createChildren(
        address implementation
    ) public returns (address, address) {
        return _createChildren(implementation);
    }

    function authorizationCheck(address _dummy) public view {
        _authorizeUpgrade(_dummy);
    }
}
