pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "./ForkStructure.sol";

abstract contract ForkableUUPS is ForkStructure, UUPSUpgradeable, Ownable {
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _createChildren(
        address implementation
    ) internal returns (address, address) {
        address forkingManager1 = ClonesUpgradeable.clone(_getImplementation());
        children[0] = forkingManager1;
        address forkingManager2 = ClonesUpgradeable.clone(implementation);
        children[1] = forkingManager2;
        return (children[0], children[1]);
    }
}
