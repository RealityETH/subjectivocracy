/*
Deployment loosely based on the upstream 3_deployContracts.ts

NB Upstream Polygon administers things with a ProxyAdmin controlled by a Timelock.
For simplicity we remove the timelock and have the ProxyAdmin controlled purely by an EOA.
Ultimately we will have our own custom system for controlling L1 upgrades.

We also remove the deploy_ongoing stuff as the only deployment here is done by create2.
*/


/* eslint-disable no-await-in-loop, no-use-before-define, no-lonely-if, import/no-dynamic-require, global-require */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved, no-restricted-syntax */
const path = require('path');
const fs = require('fs');
const { expect } = require('chai');
const { ethers, upgrades } = require('hardhat');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

const { create2Deployment } = require('./helpers/deployment-helpers');
const commonDeployment = require('./common');
const common = require('../common/common');

const pathOutputJson = path.join(__dirname, './deploy_output.json');
const generated = require('./deploy_generated.json');

const deployParameters = require('./deploy_parameters.json');
const genesis = require('./genesis.json');

const pathOZUpgradability = path.join(__dirname, `../.openzeppelin/${process.env.HARDHAT_NETWORK}.json`);
const parentContract = ethers.constants.AddressZero;

async function doSpawnInstance() {
    // Check that there's no previous OZ deployment
    if (fs.existsSync(pathOZUpgradability)) {
        throw new Error(`There's upgradability information from previous deployments, it's mandatory to erase them before start a new one, path: ${pathOZUpgradability}`);
    }

    // Constant variables
    const networkIDMainnet = 0;

    /*
     * Check deploy parameters
     * Check that every necessary parameter is fullfilled
     */
    const mandatoryDeploymentParameters = [
        'trustedSequencerURL',
        'networkName',
        'version',
        'forkPreparationTime',
        'trustedSequencer',
        'chainID',
        'admin',
        'minter',
        'trustedAggregator',
        'trustedAggregatorTimeout',
        'pendingStateTimeout',
        'forkID',
        'zkEVMOwner',
        // 'timelockAddress',
        'minDelayTimelock',
        'salt',
        'zkEVMDeployerAddress',
        'hardAssetManagerAddress',
        'arbitrationFee',
    ];
    common.verifyDeploymentParameters(mandatoryDeploymentParameters, deployParameters);

    const mandatoryImplementationAddresses = [
        'createChildren',
        'bridgeAssetOperations',
        'forkableBridge',
        'forkonomicToken',
        'chainIdManager',
        'forkableZkEVM',
        'forkableGlobalExitRoot',
        'forkingManager'
    ]
    common.verifyDeploymentParameters(mandatoryImplementationAddresses, generated);

    const {
        realVerifier,
        trustedSequencerURL,
        networkName,
        version,
        forkPreparationTime,
        trustedSequencer,
        chainID,
        admin,
        minter,
        trustedAggregator,
        trustedAggregatorTimeout,
        pendingStateTimeout,
        forkID,
        zkEVMOwner,
        // timelockAddress,
        minDelayTimelock,
        salt,
        zkEVMDeployerAddress,
        hardAssetManagerAddress,
        arbitrationFee,
    } = deployParameters;

    const currentProvider = await common.loadProvider(deployParameters, process.env);
    const deployer = await common.loadDeployer(currentProvider, deployParameters);

    // deploy PolygonZkEVMM
    const genesisRootHex = genesis.root;

    const deploymentConfig = [
        genesisRootHex,
        trustedSequencerURL,
        networkName,
        version,
        generated['verifierContract'],
        minter,
        'Backstop0',
        'BOP0',
        arbitrationFee,
        generated['chainIdManager'],
        forkPreparationTime,
        hardAssetManagerAddress,
        0,
        ethers.constants.HashZero, // TODO: Do we need to fill in lastMainnetExitRoot?
        ethers.constants.HashZero, // TODO: Do we need to fill in lastRollupExitRoot?
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
    ];

    const polygonZkEVMParams = [
        admin,
        trustedSequencer,
        pendingStateTimeout,
        trustedAggregator,
        trustedAggregatorTimeout,
        chainID,
        forkID,
        0
    ];

    // We run spawnInstance against the implementation contract
    const forkingManagerFactory = await ethers.getContractFactory('ForkingManager', {'libraries': {'CreateChildren': generated['createChildren']}});
    const forkingManagerImplContract = forkingManagerFactory.attach(generated['forkingManager']);
    const signedForkingManagerImplContract = forkingManagerImplContract.connect(deployer);
    deploymentBlockNumber = -1;
    const deployedCode = await deployer.provider.getCode(generated['forkableZkEVMPredicted']);
    if (deployedCode === '0x') {
        const tx = await forkingManagerImplContract.spawnInstance(
            generated['proxyAdmin'],
            generated['forkableZkEVM'],
            generated['forkableBridge'],
            generated['forkonomicToken'],
            generated['forkableGlobalExitRoot'],
            deploymentConfig,
            polygonZkEVMParams
        );

        // console.log('tx', tx);
        const receipt = await tx.wait();
        deploymentBlockNumber = receipt.blockNumber;

        // Receipts should holdlog events from the proxy including our predicted addresses
        // console.log(receipt.logs);

    } else {
        console.log('Already called spawnInstance with this salt. Change the salt and redeploy.');
        console.log('If you are sure the deployment is correct you can instead fill in block number manually.');
    }

    // Check deployment
    expect('0x').not.to.be.equal(await deployer.provider.getCode(generated['forkableZkEVMPredicted']));
    expect('0x').not.to.be.equal(await deployer.provider.getCode(generated['forkableBridgePredicted']));
    expect('0x').not.to.be.equal(await deployer.provider.getCode(generated['forkableGlobalExitRootPredicted']));
    expect('0x').not.to.be.equal(await deployer.provider.getCode(generated['forkingManagerPredicted']));
    expect('0x').not.to.be.equal(await deployer.provider.getCode(generated['forkonomicTokenPredicted']));

    const forkingManagerDeployedContract = forkingManagerFactory.attach(generated['forkingManagerPredicted']);
    expect(await forkingManagerDeployedContract.zkEVM()).to.be.equal(generated['forkableZkEVMPredicted']);
    expect(await forkingManagerDeployedContract.bridge()).to.be.equal(generated['forkableBridgePredicted']);
    expect(await forkingManagerDeployedContract.forkonomicToken()).to.be.equal(generated['forkonomicTokenPredicted']);
    expect(await forkingManagerDeployedContract.globalExitRoot()).to.be.equal(generated['forkableGlobalExitRootPredicted']);

    const outputJson = {
         polygonZkEVMAddress: generated['forkableZkEVMPredicted'],
         polygonZkEVMBridgeAddress: generated['forkableBridgePredicted'],
         polygonZkEVMGlobalExitRootAddress: generated['forkableGlobalExitRootPredicted'],
         forkingManager: generated['forkingManagerPredicted'],
         maticTokenAddress: generated['forkonomicTokenPredicted'],
         createChildrenImplementationAddress: generated['createChildren'],
         bridgeOperationImplementationAddress: generated['bridgeAssetOperations'],
         bridgeImplementationAddress: generated['forkableBridge'],
         verifierAddress: generated['verifierContract'],
         zkEVMDeployerContract: generated['zkEVMDeployerAddress'],
         deployerAddress: deployer.address,
         timelockContractAddress: null,
         deploymentBlockNumber: deploymentBlockNumber,
         genesisRoot: genesisRootHex,
         trustedSequencer: trustedSequencer,
         trustedSequencerURL: trustedSequencerURL,
         chainID: chainID,
         networkName: networkName,
         admin: admin,
         trustedAggregator: trustedAggregator,
         proxyAdminAddress: generated['proxyAdmin'],
         forkID: forkID,
         salt: salt,
         version: version,
         minter: minter
    };

    return outputJson;

}

async function main() {
    const output = await doSpawnInstance();
    fs.writeFileSync(pathOutputJson, JSON.stringify(output, null, 1));
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
