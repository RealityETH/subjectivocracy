// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

interface IForkableStructure {
    function forkmanager() external view returns (address);

    function parentContract() external view returns (address);

    function getChildren() external view returns (address, address);
}
