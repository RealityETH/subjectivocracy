pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./ForkStructure.sol";

abstract contract ForkableUUPS is ForkStructure, UUPSUpgradeable, Ownable {
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
