/* eslint-disable import/no-dynamic-require, global-require */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved, no-restricted-syntax */
const path = require('path');
const { ethers } = require('hardhat');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const common = require('../common/common');

async function main() {
    /*
     * Check deploy parameters
     * Check that every necessary parameter is fullfilled
     */
    const args = process.argv.slice(2);
    const deploymentName = args[0];
    const deployParameters = require(`../../deployments/${deploymentName}/deploy_parameters.json`);
    const deploymentOutput = require(`../../deployments/${deploymentName}/deploy_output.json`);

    const mandatoryDeploymentOutput = [
        'polygonZkEVMAddress',
        'polygonZkEVMGlobalExitRootAddress',
        'deployerAddress',
    ];
    for (const parameterName of mandatoryDeploymentOutput) {
        if (deploymentOutput[parameterName] === undefined || deploymentOutput[parameterName] === '') {
            throw new Error(`Missing parameter: ${parameterName}`);
        }
    }
    const {
        polygonZkEVMAddress,
        polygonZkEVMGlobalExitRootAddress,
    } = deploymentOutput;

    const currentProvider = await common.loadProvider(deployParameters, process.env);
    const deployer = await common.loadDeployer(currentProvider, deployParameters);

    const zkevm = (await ethers.getContractAt(
        'contracts/ForkableZkEVM.sol:ForkableZkEVM',
        polygonZkEVMAddress,
    )).connect(deployer);

    let children = await zkevm.connect(deployer).getChildren();
    const zkevmChild = (await ethers.getContractAt(
        'contracts/ForkableZkEVM.sol:ForkableZkEVM',
        children[1],
    )).connect(deployer);
    console.log('batch old', await zkevm.lastBatchSequenced(), 'batch child', await zkevmChild.lastBatchSequenced());
    const batchNr = await zkevm.lastBatchSequenced();
    console.log('stateroot old', await zkevm.batchNumToStateRoot(batchNr), 'stateroot child', await zkevmChild.batchNumToStateRoot(batchNr));
    console.log('trustedSequencer old', await zkevm.trustedSequencer(), 'stateroot child', await zkevmChild.trustedSequencer());

    const globalExitRoot = (await ethers.getContractAt(
        'contracts/ForkableGlobalExitRoot.sol:ForkableGlobalExitRoot',
        polygonZkEVMGlobalExitRootAddress,
    )).connect(deployer);
    children = await globalExitRoot.connect(deployer).getChildren();
    const globalExitRootChild = (await ethers.getContractAt(
        'contracts/ForkableGlobalExitRoot.sol:ForkableGlobalExitRoot',
        children[1],
    )).connect(deployer);

    console.log(
        'batch old',
        await globalExitRoot.getLastGlobalExitRoot(),
        'batch child',
        await globalExitRootChild.getLastGlobalExitRoot(),
    );
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
