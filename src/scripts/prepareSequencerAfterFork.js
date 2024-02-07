/* eslint-disable no-await-in-loop, no-use-before-define, no-lonely-if, import/no-dynamic-require, global-require */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved, no-restricted-syntax */
const path = require('path');
const { ethers } = require('hardhat');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const common = require('../common/common');

const ChildConfig = {
    firstChild: 0,
    secondChild: 1,
};

async function main() {
    const childConfig = ChildConfig.secondChild;
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
        'maticTokenAddress',
        'trustedSequencer',
    ];
    for (const parameterName of mandatoryDeploymentOutput) {
        if (deploymentOutput[parameterName] === undefined || deploymentOutput[parameterName] === '') {
            throw new Error(`Missing parameter: ${parameterName}`);
        }
    }
    const {
        polygonZkEVMAddress,
        maticTokenAddress,
        trustedSequencer,
    } = deploymentOutput;

    const forkonomicTokenAddress = maticTokenAddress;
    const currentProvider = await common.loadProvider(deployParameters, process.env);
    const deployer = await common.loadDeployer(currentProvider, deployParameters);


    if (trustedSequencer === undefined || trustedSequencer.toLowerCase() !== deployer.address.toLowerCase()) {
        throw new Error('Wrong deployer address');
    }
    console.log('polygonZkEVMAddress: ', polygonZkEVMAddress);
    const zkevm = (await ethers.getContractAt(
        'contracts/ForkableZkEVM.sol:ForkableZkEVM',
        polygonZkEVMAddress,
    )).connect(deployer);
    const zkevmChildren = await zkevm.getChildren();
    const zkevmChildAddress = zkevmChildren[childConfig];

    const forkonomicToken = (await ethers.getContractAt(
        'contracts/ForkonomicToken.sol:ForkonomicToken',
        forkonomicTokenAddress,
    )).connect(deployer);
    const children = await forkonomicToken.getChildren();
    const forkonomicTokenChild = (await ethers.getContractAt(
        'contracts/ForkonomicToken.sol:ForkonomicToken',
        children[childConfig],
    )).connect(deployer);

    const tx1 = await forkonomicTokenChild.approve(zkevmChildAddress, ethers.constants.MaxUint256);
    console.log('Approved zkevm to spend forkonomic tokens');
    console.log('by the following tx: ', tx1.hash);

    const splitAmount = await forkonomicToken.balanceOf(deployer.address);
    const tx2 = await forkonomicTokenChild.splitTokensIntoChildTokens(splitAmount, { gasLimit: 1000000 });
    console.log('Splitting tokens into their child tokens');
    console.log('by the following tx: ', tx2.hash);
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
