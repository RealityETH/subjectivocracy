/* eslint-disable no-await-in-loop, no-use-before-define, no-lonely-if, import/no-dynamic-require, global-require */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved, no-restricted-syntax */
const path = require('path');
const { ethers } = require('hardhat');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

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

    // Load provider
    const currentProvider = await common.loadProvider(deployParameters, process.env);
    const deployer = await common.loadDeployer(currentProvider, deployParameters);
 

    if (trustedSequencer === undefined || trustedSequencer.toLowerCase() !== deployer.address.toLowerCase()) {
        throw new Error('Wrong deployer address');
    }

    const zkevm = await ethers.getContractAt(
        'contracts/ForkableZkEVM.sol:ForkableZkEVM',
        polygonZkEVMAddress,
    );

    const forkonomicToken = await ethers.getContractAt(
        'contracts/ForkonomicToken.sol:ForkonomicToken',
        forkonomicTokenAddress,
    );
    const children = await forkonomicToken.getChildren();
    const forkonomicTokenChild = 
    await ethers.getContractAt(
        'contracts/ForkonomicToken.sol:ForkonomicToken',
        children.children[0],
        );

    const depositAmount = ethers.utils.parseEther('10');
    const tx1 = await forkonomicTokenChild.connect(deployer).approve(polygonZkEVMAddress, ethers.constants.MaxUint256);
    console.log('Approved zkevm to spend forkonomic tokens');
    console.log('by the following tx: ', tx1.hash);


    const tx2 = await forkonomicToken.connect(deployer).bridgeAsset(
        1,
        deployer.address,
        depositAmount,
        forkonomicTokenAddress,
        true,
        '0x',
        { gasLimit: 5000000 },
    );
    console.log('Deposited forkonomic tokens into bridge');
    console.log('by the following tx: ', tx2.hash);
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
