pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./ForkStructure.sol";

abstract contract ForkableUUPS is ForkStructure, UUPSUpgradeable, Ownable {
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _createChildren(
        address implementation
    ) internal returns (address forkingManager1, address forkingManager2) {
        forkingManager1 = address(new ERC1967Proxy(_getImplementation(), ""));
        children[0] = forkingManager1;
        forkingManager2 = address(new ERC1967Proxy(implementation, ""));
        children[1] = forkingManager2;
    }
}
