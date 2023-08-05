// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

// The following dependency is only needed for deployment
import {PolygonZkEVMDeployer} from "@RealityETH/zkevm-contracts/contracts/deployment/PolygonZkEVMDeployer.sol";

// This contract only exists to laod dependencies that are not interherited by an other contract, but still needed
// by the repo
contract Getter {

}
