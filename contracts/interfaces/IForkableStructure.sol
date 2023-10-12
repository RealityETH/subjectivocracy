// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

interface IForkableStructure {
    function getChildren() external view returns (address, address);
}
