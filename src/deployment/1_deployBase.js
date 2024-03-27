// This deploys the keyless deployer, then uses it deploy implementations with create2

/* eslint-disable no-await-in-loop, no-use-before-define, no-lonely-if, import/no-dynamic-require, global-require */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved, no-restricted-syntax */
const path = require('path');
const fs = require('fs');
const { ethers, upgrades } = require('hardhat');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const { expect } = require('chai');
const { deployPolygonZkEVMDeployer } = require('./helpers/deployment-helpers');

const { create2Deployment } = require('./helpers/deployment-helpers');
const deployParameters = require('./deploy_parameters.json');

const generatedPath = path.join(__dirname, './deploy_generated.json');

const pathDeployParameters = path.join(__dirname, './deploy_parameters.json');

const commonDeployment = require('./common');
const common = require('../common/common');

async function doDeployBase() {

    // Hardhat needs a special gas override to avoid errors about the block gas limit.
    // Sepolia doesn't seem to care.
    const overrideGasLimit = (process.env.HARDHAT_NETWORK == 'hardhat') ? ethers.BigNumber.from(6500000) : null;

    let generated = {};

    const currentProvider = await common.loadProvider(deployParameters, process.env);
    const deployer = await common.loadDeployer(currentProvider, deployParameters);
    console.log('Deployer: ', deployer.address);

    // Load initialZkEVMDeployerOwner
    let {
        realVerifier,
        chainID,
        admin,
        initialZkEVMDeployerOwner,
        salt,
        maticTokenAddressFromConfig
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
    generated['zkEVMDeployerAddress'] = zkEVMDeployerContract.address;

    expect(deployer.address).to.be.equal(await zkEVMDeployerContract.owner());

    generated['createChildren'] = await commonDeployment.create2Deploy(zkEVMDeployerContract, salt, deployer, 'CreateChildren', [], overrideGasLimit, null, true); 
    generated['bridgeAssetOperations'] = await commonDeployment.create2Deploy(zkEVMDeployerContract, salt, deployer, 'BridgeAssetOperations', []);

    const bridgeLibs = {
        CreateChildren: generated['createChildren'],
        BridgeAssetOperations: generated['bridgeAssetOperations']
    }

    generated['forkableBridge'] = await commonDeployment.create2Deploy(zkEVMDeployerContract, salt, deployer, 'ForkableBridge', [], overrideGasLimit, bridgeLibs);

    const forkableLibs = {
        CreateChildren: generated['createChildren']
    }

    generated['forkonomicToken'] = await commonDeployment.create2Deploy(zkEVMDeployerContract, salt, deployer, 'ForkonomicToken', [], overrideGasLimit, forkableLibs);
    generated['chainIdManager'] = await commonDeployment.create2Deploy(zkEVMDeployerContract, salt, deployer, 'ChainIdManager', [chainID]);

    const verifierPath = realVerifier ? '@RealityETH/zkevm-contracts/contracts/verifiers/FflonkVerifier.sol:FflonkVerifier' : '@RealityETH/zkevm-contracts/contracts/mocks/VerifierRollupHelperMock.sol:VerifierRollupHelperMock';
    generated['verifierContract'] = await commonDeployment.create2Deploy(zkEVMDeployerContract, salt, deployer, verifierPath, []);
    generated['forkableZkEVM'] = await commonDeployment.create2Deploy(zkEVMDeployerContract, salt, deployer, 'ForkableZkEVM', [], overrideGasLimit, forkableLibs);
    generated['forkableGlobalExitRoot'] = await commonDeployment.create2Deploy(zkEVMDeployerContract, salt, deployer, 'ForkableGlobalExitRoot', [], overrideGasLimit, forkableLibs);

    generated['forkingManager'] = await commonDeployment.create2Deploy(zkEVMDeployerContract, salt, deployer, 'ForkingManager', [], overrideGasLimit, forkableLibs); 

    /*
     * We use a Proxy Admin to control the contracts instead of an EOA as recommended here:
     * https://docs.openzeppelin.com/contracts/4.x/api/proxy#TransparentUpgradeableProxy
     * Do not initialize directly the proxy since we want to deploy the same code on L2 and this will alter the bytecode deployed of the proxy
     */
    const proxyAdminPath = "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin";
    const proxyAdminFactory = await ethers.getContractFactory(proxyAdminPath, deployer);
    const dataCallAdmin = proxyAdminFactory.interface.encodeFunctionData("transferOwnership", [admin]);
    generated['proxyAdmin'] = await commonDeployment.create2Deploy(zkEVMDeployerContract, salt, deployer, proxyAdminPath, [], overrideGasLimit, null, dataCallAdmin); 

    // We use the forking manager implementation to spawn the instances
    // TODO: This might be better as a separate contract sharing relevant parts with ForkingManager
//    const forkingManagerFactory = await ethers.getContractFactory('ForkingManager', {signer: deployer, libraries: forkableLibs, unsafeAllowLinkedLibraries: true});
    const spawner = generated['forkingManager'];

    generated['forkableGlobalExitRootPredicted'] = await commonDeployment.predictTransparentProxyAddress(spawner, generated['forkableGlobalExitRoot'], generated['proxyAdmin'], deployer.address);
    generated['forkableZkEVMPredicted'] = await commonDeployment.predictTransparentProxyAddress(spawner, generated['forkableZkEVM'], generated['proxyAdmin'], deployer.address);
    generated['forkingManagerPredicted'] = await commonDeployment.predictTransparentProxyAddress(spawner, generated['forkingManager'], generated['proxyAdmin'], deployer.address);
    generated['forkonomicTokenPredicted'] = await commonDeployment.predictTransparentProxyAddress(spawner, generated['forkonomicToken'], generated['proxyAdmin'], deployer.address);
    generated['forkableBridgePredicted'] = await commonDeployment.predictTransparentProxyAddress(spawner, generated['forkableBridge'], generated['proxyAdmin'], deployer.address);

    return generated;

}

async function main() {
    const generated = await doDeployBase();
    fs.writeFileSync(generatedPath, JSON.stringify(generated, null, 1));
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
