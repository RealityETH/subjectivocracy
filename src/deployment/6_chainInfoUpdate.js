/* eslint-disable no-await-in-loop, import/no-dynamic-require */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved */

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });
const { ethers } = require('hardhat');

const pathOutputJsonL1System = path.join(__dirname, './deploy_output.json');
const pathOutputJsonL1Applications = path.join(__dirname, './deploy_output_l1_applications.json');
const pathOutputJsonL2Applications = path.join(__dirname, './deploy_output_l2_applications.json');

const l1Applications = require(pathOutputJsonL1Applications);
const l2Applications = require(pathOutputJsonL2Applications);
const l1SystemAddresses = require(pathOutputJsonL1System);

async function main() {
    const currentProvider = ethers.provider;
    let deployer;
    if (process.env.PVTKEY) {
        deployer = new ethers.Wallet(process.env.PVTKEY, currentProvider);
        console.log('Using pvtKey deployer with address: ', deployer.address);
    } else if (process.env.MNEMONIC) {
        deployer = ethers.Wallet.fromMnemonic(process.env.MNEMONIC, 'm/44\'/60\'/0\'/0/0').connect(currentProvider);
        console.log('Using MNEMONIC deployer with address: ', deployer.address);
    } else {
        [deployer] = (await ethers.getSigners());
    }

    const l1BridgeAddress = l1SystemAddresses.polygonZkEVMBridgeAddress;

    const l1GlobalChainInfoPublisherFactory = await ethers.getContractFactory('L1GlobalChainInfoPublisher', {
        signer: deployer,
    });
    const l1GlobalChainInfoPublisher = l1GlobalChainInfoPublisherFactory.attach(l1Applications.l1GlobalChainInfoPublisher);

    console.log('sending chain info update with addresses', l1BridgeAddress, l2Applications.l2ChainInfo);
    const result = await l1GlobalChainInfoPublisher.updateL2ChainInfo(
        l1BridgeAddress,
        l2Applications.l2ChainInfo,
        ethers.constants.AddressZero,
        ethers.constants.AddressZero,
    );
    console.log('sent tx, hash is', result.hash);
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
