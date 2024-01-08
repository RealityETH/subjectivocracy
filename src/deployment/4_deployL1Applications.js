/* eslint-disable no-await-in-loop, no-use-before-define, no-lonely-if, import/no-dynamic-require, global-require */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved, no-restricted-syntax */
const path = require('path');
const fs = require('fs');
const { ethers } = require('hardhat');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

const pathOutputJson = path.join(__dirname, './deploy_output_l1_applications.json');
const pathOngoingDeploymentJson = path.join(__dirname, './deploy_ongoing_l1_applications.json');

const deployParameters = {};

const delay = ms => new Promise(res => setTimeout(res, ms));

const common = require('./common.js');

async function main() {

    // Check if there's an ongoing deployment
    let ongoingDeployment = {};
    if (fs.existsSync(pathOngoingDeploymentJson)) {
        ongoingDeployment = require(pathOngoingDeploymentJson);
    }

    // Load provider
    let currentProvider = await common.loadProvider(deployParameters, process.env);
    let deployer = await common.loadDeployer(currentProvider, deployParameters);

    let deployerBalance = await currentProvider.getBalance(deployer.address);
    console.log('using deployer: ', deployer.address, 'balance is ', deployerBalance.toString());

    const l1GlobalChainInfoPublisherContract = await common.loadOngoingOrDeploy(deployer, 'L1GlobalChainInfoPublisher', 'l1GlobalChainInfoPublisher', [], ongoingDeployment, pathOngoingDeploymentJson);
    const l1GlobalForkRequesterContract =  await common.loadOngoingOrDeploy(deployer, 'L1GlobalForkRequester', 'l1GlobalForkRequester', [], ongoingDeployment, pathOngoingDeploymentJson);

    const outputJson = {
        l1GlobalChainInfoPublisher: l1GlobalChainInfoPublisherContract.address,
        l1GlobalForkRequester: l1GlobalForkRequesterContract.address,
    };
    fs.writeFileSync(pathOutputJson, JSON.stringify(outputJson, null, 1));

    // Remove ongoing deployment
    fs.unlinkSync(pathOngoingDeploymentJson);
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
