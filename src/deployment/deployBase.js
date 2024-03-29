// This deploys the keyless deployer, then uses it deploy implementations with create2

/* eslint-disable no-await-in-loop, no-use-before-define, no-lonely-if, import/no-dynamic-require, global-require */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved, no-restricted-syntax */
const { ethers, upgrades } = require('hardhat');
const { expect } = require('chai');
const { deployPolygonZkEVMDeployer } = require('./helpers/deployment-helpers');

const { create2Deploy, predictTransparentProxyAddress } = require('./common');
const common = require('../common/common');

async function doDeployBase(deployParameters) {
    /*
     * Hardhat needs a special gas override to avoid errors about the block gas limit.
     * Sepolia doesn't seem to care.
     */
    const overrideGasLimit = (process.env.HARDHAT_NETWORK === 'hardhat') ? ethers.BigNumber.from(6500000) : null;

    const generated = {};

    const currentProvider = await common.loadProvider(deployParameters, process.env);
    const deployer = await common.loadDeployer(currentProvider, deployParameters);
    console.log('Deployer: ', deployer.address);

    // Load initialZkEVMDeployerOwner
    const {
        realVerifier,
        chainID,
        admin,
        salt,
    } = deployParameters;

    let {
        initialZkEVMDeployerOwner,
    } = deployParameters;

    if (!initialZkEVMDeployerOwner) {
        initialZkEVMDeployerOwner = deployer.address;
        console.log('initialZkEVMDeployerOwner not set, using deployer,', initialZkEVMDeployerOwner);
    }

    // Deploy PolygonZkEVMDeployer if is not deployed already using keyless deployment
    const [zkEVMDeployerContract, keylessDeployer] = await deployPolygonZkEVMDeployer(initialZkEVMDeployerOwner, deployer);
    if (keylessDeployer === ethers.constants.AddressZero) {
        console.log('PolygonZkEVMDeployer was already deployed on: ', zkEVMDeployerContract.address);
    } else {
        console.log('PolygonZkEVMDeployer deployed on: ', zkEVMDeployerContract.address);
    }
    generated.zkEVMDeployerAddress = zkEVMDeployerContract.address;

    expect(deployer.address).to.be.equal(await zkEVMDeployerContract.owner());

    generated.createChildren = await create2Deploy(zkEVMDeployerContract, salt, deployer, 'CreateChildren', [], overrideGasLimit, null, true);
    generated.bridgeAssetOperations = await create2Deploy(zkEVMDeployerContract, salt, deployer, 'BridgeAssetOperations', []);

    const bridgeLibs = {
        CreateChildren: generated.createChildren,
        BridgeAssetOperations: generated.bridgeAssetOperations,
    };

    generated.forkableBridge = await create2Deploy(zkEVMDeployerContract, salt, deployer, 'ForkableBridge', [], overrideGasLimit, bridgeLibs);

    const forkableLibs = {
        CreateChildren: generated.createChildren,
    };

    generated.forkonomicToken = await create2Deploy(zkEVMDeployerContract, salt, deployer, 'ForkonomicToken', [], overrideGasLimit, forkableLibs);
    generated.chainIdManager = await create2Deploy(zkEVMDeployerContract, salt, deployer, 'ChainIdManager', [chainID]);

    const verifierPath = realVerifier ? '@RealityETH/zkevm-contracts/contracts/verifiers/FflonkVerifier.sol:FflonkVerifier' : '@RealityETH/zkevm-contracts/contracts/mocks/VerifierRollupHelperMock.sol:VerifierRollupHelperMock';
    generated.verifierContract = await create2Deploy(zkEVMDeployerContract, salt, deployer, verifierPath, []);
    generated.forkableZkEVM = await create2Deploy(zkEVMDeployerContract, salt, deployer, 'ForkableZkEVM', [], overrideGasLimit, forkableLibs);
    generated.forkableGlobalExitRoot = await create2Deploy(zkEVMDeployerContract, salt, deployer, 'ForkableGlobalExitRoot', [], overrideGasLimit, forkableLibs);

    generated.forkingManager = await create2Deploy(zkEVMDeployerContract, salt, deployer, 'ForkingManager', [], overrideGasLimit, forkableLibs);

    /*
     * We use a Proxy Admin to control the contracts instead of an EOA as recommended here:
     * https://docs.openzeppelin.com/contracts/4.x/api/proxy#TransparentUpgradeableProxy
     * Do not initialize directly the proxy since we want to deploy the same code on L2 and this will alter the bytecode deployed of the proxy
     */
    const proxyAdminPath = '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin';
    const proxyAdminFactory = await ethers.getContractFactory(proxyAdminPath, deployer);
    const dataCallAdmin = proxyAdminFactory.interface.encodeFunctionData('transferOwnership', [admin]);
    const proxyAdmin = await create2Deploy(zkEVMDeployerContract, salt, deployer, proxyAdminPath, [], overrideGasLimit, null, dataCallAdmin);
    generated.proxyAdmin = proxyAdmin;

    /*
     * We use the forking manager implementation to spawn the instances
     * TODO: This might be better as a separate contract sharing relevant parts with ForkingManager
     *    const forkingManagerFactory = await ethers.getContractFactory('ForkingManager', {signer: deployer, libraries: forkableLibs, unsafeAllowLinkedLibraries: true});
     */
    const spawner = generated.forkingManager;

    generated.forkableGlobalExitRootPredicted = await predictTransparentProxyAddress(spawner, generated.forkableGlobalExitRoot, proxyAdmin, deployer.address);
    generated.forkableZkEVMPredicted = await predictTransparentProxyAddress(spawner, generated.forkableZkEVM, proxyAdmin, deployer.address);
    generated.forkingManagerPredicted = await predictTransparentProxyAddress(spawner, generated.forkingManager, proxyAdmin, deployer.address);
    generated.forkonomicTokenPredicted = await predictTransparentProxyAddress(spawner, generated.forkonomicToken, proxyAdmin, deployer.address);
    generated.forkableBridgePredicted = await predictTransparentProxyAddress(spawner, generated.forkableBridge, proxyAdmin, deployer.address);

    return generated;
}

module.exports = {
    doDeployBase
}
