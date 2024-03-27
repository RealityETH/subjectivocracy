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

async function main() {

    // Hardhat needs a special gas override to avoid errors about the block gas limit.
    // Sepolia doesn't seem to care.
    const overrideGasLimit = (process.env.HARDHAT_NETWORK == 'hardhat') ? ethers.BigNumber.from(6500000) : null;

    // Check if there's an ongoing deployment
    let generated = {};
    if (fs.existsSync(generatedPath)) {
        generated = require(generatedPath);
    }

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

    expect(deployer.address).to.be.equal(await zkEVMDeployerContract.owner());

    const createChildrenImplementationContract = await commonDeployment.loadOngoingOrDeployCreate2(zkEVMDeployerContract, salt, deployer, 'CreateChildren', 'createChildren', [], generated, generatedPath, overrideGasLimit, null, true); 

    const bridgeAssetOperationImplementationContract =  await commonDeployment.loadOngoingOrDeployCreate2(zkEVMDeployerContract, salt, deployer, 'BridgeAssetOperations', 'bridgeAssetOperations', [], generated, generatedPath);

    const bridgeLibs = {
        CreateChildren: createChildrenImplementationContract.address,
        BridgeAssetOperations: bridgeAssetOperationImplementationContract.address
    }

    // TODO I wanted to use create2 for this but it runs into some block size limitation with hardhat
    //const bridgeImplementationContract =  await commonDeployment.loadOngoingOrDeployCreate2(zkEVMDeployerContract, salt, deployer, 'ForkableBridge', 'forkableBridge', [], generated, generatedPath, null, bridgeLibs);
    const forkableBridgeImplementationContract = await commonDeployment.loadOngoingOrDeployCreate2(zkEVMDeployerContract, salt, deployer, 'ForkableBridge', 'forkableBridge', [], generated, generatedPath, overrideGasLimit, bridgeLibs);

    const forkableLibs = {
        CreateChildren: createChildrenImplementationContract.address
    }

    const forkonomicTokenImplementationContract = await commonDeployment.loadOngoingOrDeployCreate2(zkEVMDeployerContract, salt, deployer, 'ForkonomicToken', 'forkonomicToken', [], generated, generatedPath, null, forkableLibs);

    const chainIdManagerContract = await commonDeployment.loadOngoingOrDeployCreate2(zkEVMDeployerContract, salt, deployer, 'ChainIdManager', 'chainIdManager', [chainID], generated, generatedPath);

    const verifierPath = realVerifier ? '@RealityETH/zkevm-contracts/contracts/verifiers/FflonkVerifier.sol:FflonkVerifier' : '@RealityETH/zkevm-contracts/contracts/mocks/VerifierRollupHelperMock.sol:VerifierRollupHelperMock';
    const verifierContract = await commonDeployment.loadOngoingOrDeployCreate2(zkEVMDeployerContract, salt, deployer, verifierPath, 'verifierContract', [], generated, generatedPath);

    const forkableZkEVMImplmentationContract = await commonDeployment.loadOngoingOrDeployCreate2(zkEVMDeployerContract, salt, deployer, 'ForkableZkEVM', 'forkableZkEVM', [], generated, generatedPath, overrideGasLimit, forkableLibs);

    const forkableGlobalExitRootImplementationContract = await commonDeployment.loadOngoingOrDeployCreate2(zkEVMDeployerContract, salt, deployer, 'ForkableGlobalExitRoot', 'forkableGlobalExitRoot', [], generated, generatedPath, null, forkableLibs);

    const forkingManagerImplementationContract = await commonDeployment.loadOngoingOrDeployCreate2(zkEVMDeployerContract, salt, deployer, 'ForkingManager', 'forkingManager', [], generated, generatedPath, overrideGasLimit, forkableLibs); 

    /*
     * We use a Proxy Admin to control the contracts instead of an EOA as recommended here:
     * https://docs.openzeppelin.com/contracts/4.x/api/proxy#TransparentUpgradeableProxy
     * Do not initialize directly the proxy since we want to deploy the same code on L2 and this will alter the bytecode deployed of the proxy
     */
    const proxyAdminPath = "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin";
    const proxyAdminFactory = await ethers.getContractFactory(proxyAdminPath, deployer);
    const dataCallAdmin = proxyAdminFactory.interface.encodeFunctionData("transferOwnership", [admin]);
    const proxyAdminContract = await commonDeployment.loadOngoingOrDeployCreate2(zkEVMDeployerContract, salt, deployer, proxyAdminPath, 'proxyAdmin', [], generated, generatedPath, overrideGasLimit, null, dataCallAdmin); 
    const proxyAdminAddress = proxyAdminContract.address;

    const instanceSpawner = forkingManagerImplementationContract.address;

    const forkableGlobalExitRoot = await commonDeployment.predictTransparentProxyAddress(instanceSpawner, forkableGlobalExitRootImplementationContract.address, proxyAdminAddress, deployer.address);
    const forkableZkEVM = await commonDeployment.predictTransparentProxyAddress(instanceSpawner, forkableZkEVMImplmentationContract.address, proxyAdminAddress, deployer.address);
    const forkingManager = await commonDeployment.predictTransparentProxyAddress(instanceSpawner, forkingManagerImplementationContract.address, proxyAdminAddress, deployer.address);
    const forkonomicToken = await commonDeployment.predictTransparentProxyAddress(instanceSpawner, forkonomicTokenImplementationContract.address, proxyAdminAddress, deployer.address);
    const forkableBridge = await commonDeployment.predictTransparentProxyAddress(instanceSpawner, forkableBridgeImplementationContract.address, proxyAdminAddress, deployer.address);

    console.log('Contract deployments in step 3 will be as follows:');
    console.log('forkableGlobalExitRoot', forkableGlobalExitRoot);
    console.log('forkableZkEVM', forkableZkEVM);
    console.log('forkingManager', forkingManager)
    console.log('forkonomicToken', forkonomicToken);
    console.log('forkableBridge', forkableBridge);

    generated['forkableGlobalExitRootPredicted'] = forkableGlobalExitRoot;
    generated['forkableZkEVMPredicted'] = forkableZkEVM;
    generated['forkingManagerPredicted'] = forkingManager;
    generated['forkonomicTokenPredicted'] = forkonomicToken;
    generated['forkableBridgePredicted'] = forkableBridge;

    fs.writeFileSync(generatedPath, JSON.stringify(generated, null, 1));
    
    return;

}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
