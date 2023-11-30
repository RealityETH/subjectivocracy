// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

// The following dependency is only needed for deployment
import {PolygonZkEVMDeployer} from "@RealityETH/zkevm-contracts/contracts/deployment/PolygonZkEVMDeployer.sol";
import {PolygonZkEVMGlobalExitRootL2} from "@RealityETH/zkevm-contracts/contracts/PolygonZkEVMGlobalExitRootL2.sol";
import {PolygonZkEVMTimelock} from "@RealityETH/zkevm-contracts/contracts/PolygonZkEVMTimelock.sol";
import {VerifierRollupHelperMock} from "@RealityETH/zkevm-contracts/contracts/mocks/VerifierRollupHelperMock.sol";
import {FflonkVerifier} from "@RealityETH/zkevm-contracts/contracts/verifiers/FflonkVerifier.sol";

// This contract only exists to laod dependencies that are not interherited by an other contract, but still needed
// by the repo
contract Getter {

}
