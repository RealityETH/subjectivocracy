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

    const forkingManagerAddress = await zkevm.forkmanager();

    const forkingManager = (await ethers.getContractAt(
        'contracts/ForkingManager.sol:ForkingManager',
        forkingManagerAddress,
    )).connect(deployer);

    console.log('Owner', await zkevm.owner());
    console.log('Fork ID', (await zkevm.forkID()).toString());
    console.log('Fork Manager', forkingManagerAddress);
    console.log('Parent', await zkevm.parentContract());
    console.log('trustedSequencerURL', await zkevm.trustedSequencerURL());
    console.log('Bridge', await forkingManager.bridge());

}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
