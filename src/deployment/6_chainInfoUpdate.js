/* eslint-disable no-await-in-loop */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved */

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });
const { ethers } = require('hardhat');

const deployParameters = require('./deploy_application_parameters.json');
const l1Applications = require('./deploy_output_l1_applications.json');
const l2Applications = require('./deploy_output_l2_applications.json');
const l1SystemAddresses = require('./deploy_output.json');

const common = require('./common');

async function main() {
    const currentProvider = await common.loadProvider(deployParameters, process.env);
    const deployer = await common.loadDeployer(currentProvider, deployParameters);

    const l1BridgeAddress = l1SystemAddresses.polygonZkEVMBridgeAddress;

    const l1GlobalChainInfoPublisherFactory = await ethers.getContractFactory('L1GlobalChainInfoPublisher', {
        signer: deployer,
    });
    const l1GlobalChainInfoPublisher = l1GlobalChainInfoPublisherFactory.attach(l1Applications.l1GlobalChainInfoPublisher);

    console.log('sending chain info update with addresses', l1BridgeAddress, l2Applications.l2ChainInfo);
    const zero = ethers.constants.AddressZero;
    const result = await l1GlobalChainInfoPublisher.updateL2ChainInfo(l1BridgeAddress, l2Applications.l2ChainInfo, zero, zero);
    console.log('sent tx, hash is', result.hash);
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
