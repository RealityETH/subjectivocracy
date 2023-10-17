// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

import {IForkingManager} from "./interfaces/IForkingManager.sol";
import {IForkableBridge} from "./interfaces/IForkableBridge.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {IL2Directory} from "./interfaces/IL2Directory.sol";
import {IAMB} from "./interfaces/IAMB.sol";

contract L2Directory is IL2Directory {

    // in interface:
    // address public l2Bridge;
    // address public l1GlobalRouter;

    // Don't expose these directly because we want to check the chain ID hasn't changed before returning them
    address forkingManager;
    address l1Token;

    bytes32 dispute;
    uint8 yesOrNo;

    uint256 chainId;

    modifier onlyIfUpToDate {
        require(block.chainid == chainId, "Chain ID has changed and we have not been updated");
        _;
    }
    
    constructor(address _l2Bridge, address _l1GlobalRouter, address _initialForkingManager, address _initialL1Token) {
        l2Bridge = _l2Bridge;
        l1GlobalRouter = _l1GlobalRouter;

        chainId = block.chainid;

        l1Token = _initialL1Token; 
        forkingManager = _initialForkingManager;
    }

    // The l1GlobalRouter will report the information it gets from the bridge, then send it via the bridge.
    function updateChainInfo(address _forkingManager, address _l1Token, bytes32 _dispute, uint8 _yesOrNo) external {

        require(msg.sender == l2Bridge, "Must be from expected l2 bridge address");

        // TODO: Using the AMB syntax, zkevm etc will be different
        require(IAMB.messageSender() == l1GlobalRouter, "Chain updates must come from l1GlobalRouter");

        chainId = block.chainid;

        forkingManager = _forkingManager;
        l1Token = _l1Token;
        dispute = _dispute;
        yesOrNo = _yesOrNo;
    }

    function getForkingManager() onlyIfUpToDate external view returns (address) {
        return forkingManager;
    }

    function getL1Token() onlyIfUpToDate external view returns (address) {
        return l1Token;
    }

    function getDispute() onlyIfUpToDate external view returns (bytes32) {
        return dispute;
    }

    function getYesOrNo() onlyIfUpToDate external view returns (uint8) {
        return yesOrNo;
    }

}
