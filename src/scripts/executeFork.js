/* eslint-disable no-await-in-loop, no-use-before-define, no-lonely-if, import/no-dynamic-require, global-require */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved, no-restricted-syntax */
const path = require('path');
const { ethers } = require('hardhat');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

const common = require('../common/common');


async function main() {
    const args = process.argv.slice(2);
    const deploymentName = args[0];
    const deployParameters = require(`../../deployments/${deploymentName}/deploy_parameters.json`);
    const deploymentOutput = require(`../../deployments/${deploymentName}/deploy_output.json`);

    const mandatoryDeploymentOutput = [
        'maticTokenAddress',
        'forkingManager',
    ];
    const {
        maticTokenAddress,
        forkingManager,
    } = deploymentOutput;

    common.verifyDeploymentParameters(mandatoryDeploymentOutput, deploymentOutput);

    const forkonomicTokenAddress = maticTokenAddress;

    // Load provider
    const currentProvider = await common.loadProvider(deployParameters, process.env);
    const deployer = await common.loadDeployer(currentProvider, deployParameters);

    const forkingManagerContract = (await ethers.getContractAt(
        'contracts/ForkingManager.sol:ForkingManager',
        forkingManager,
    )).connect(deployer);
    console.log('ForkingManager address: ', forkingManagerContract.address);

    const forkonomicTokenContract = (await ethers.getContractAt(
        'contracts/ForkonomicToken.sol:ForkonomicToken',
        forkonomicTokenAddress,
    )).connect(deployer);
    const payment = await forkingManagerContract.arbitrationFee();
    console.log('Payment: ', payment.toString());
    if (payment.gt(await forkonomicTokenContract.balanceOf(deployer.address))) {
        throw new Error('Not enough tokens');
    }
    console.log('Approving payment');
    await forkonomicTokenContract.connect(deployer).approve(forkingManagerContract.address, payment);
    console.log("done");
    await forkingManagerContract.connect(deployer).initiateFork('0x');
    console.log('Fork initiated');
    const sleepTime = await forkingManagerContract.forkPreparationTime();
    console.log('Sleeping for ', sleepTime, 's before executing fork');
    console.log('Alternatively, one can also execute the fork manually later on this contract: https://sepolia.etherscan.com/address/', forkingManager.address, '#writeContract');
    await new Promise((r) => setTimeout(r, sleepTime * 1000));
    const tx2 = await forkingManagerContract.connect(deployer).executeFork(payment);
    console.log('Executed fork with tx: ', tx2.hash);
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
