// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

import {IRealityETH_ERC20} from "@reality.eth/contracts/development/contracts/IRealityETH_ERC20.sol";
import {IForkableStructure} from "./IForkableStructure.sol";

// solhint-disable-next-line contract-name-camelcase
interface IForkableRealityETH_ERC20 is IForkableStructure, IRealityETH_ERC20 {

    function creditBalanceFromParent(
        address beneficiary,
        uint256 amount
    ) external;

    function l1ForkArbitrator() external returns (address);

    function createChildren() external returns (address, address);

    function initialize(
        address _forkmanager,
        address _parentContract,
        address _token,
        bytes32 _questionIdWeForkedOver
    ) external;


}
