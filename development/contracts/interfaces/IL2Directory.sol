// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

interface IL2Directory {
    address public l2Bridge;
    address public l1GlobalRouter;

    function updateChainInfo(address _forkingManager, address _l1Token, bytes32 _dispute, uint8 _yesOrNo) external ;

    function getForkingManager() external returns (address);
    function getL1Token() external returns (address);
    function getDispute() external returns (bytes32);
    function getYesOrNo() external returns (uint8);
}
