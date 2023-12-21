/* eslint-disable no-await-in-loop */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved */

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });
const { ethers } = require('hardhat');

const deployParameters = require('./deploy_application_parameters.json');

const pathOutputJsonL1System = path.join(__dirname, './deploy_output.json');
const pathOutputJsonL1Applications = path.join(__dirname, './deploy_output_l1_applications.json');
const pathOutputJsonL2Applications = path.join(__dirname, './deploy_output_l2_applications.json');

const l1Applications = require(pathOutputJsonL1Applications);
const l2Applications = require(pathOutputJsonL2Applications);
const l1SystemAddresses = require(pathOutputJsonL1System);

const common = require('./common.js');

async function main() {

    const deployParameters = require('./deploy_application_parameters.json');

    let currentProvider = await common.loadProvider(deployParameters, process.env);
    let deployer = await common.loadDeployer(currentProvider, deployParameters);

    const l1BridgeAddress = l1SystemAddresses.polygonZkEVMBridgeAddress;

    const l1GlobalChainInfoPublisherFactory = await ethers.getContractFactory('L1GlobalChainInfoPublisher', {
        signer: deployer,
    });
    const l1GlobalChainInfoPublisher = l1GlobalChainInfoPublisherFactory.attach(l1Applications.l1GlobalChainInfoPublisher);

    console.log('sending chain info update with addresses', l1BridgeAddress, l2Applications.l2ChainInfo);
    const result = await l1GlobalChainInfoPublisher.updateL2ChainInfo(l1BridgeAddress, l2Applications.l2ChainInfo, ethers.constants.AddressZero, ethers.constants.AddressZero);
    console.log('sent tx, hash is', result.hash);

}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
