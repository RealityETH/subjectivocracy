/* eslint-disable import/no-dynamic-require, no-await-in-loop, no-restricted-syntax, guard-for-in */

// Broken and/or not fully tested

require('dotenv').config();
const path = require('path');
const hre = require('hardhat');
const { expect } = require('chai');

const pathDeployParameters = path.join(__dirname, './deploy_application_parameters.json');
const pathDeployL1OutputParameters = path.join(__dirname, './deploy_output_l1_applications.json');
const pathDeployL2OutputParameters = path.join(__dirname, './deploy_output_l2_applications.json');

const deployParameters = require(pathDeployParameters);
const deployL1OutputParameters = require(pathDeployL1OutputParameters);
const deployL2OutputParameters = require(pathDeployL2OutputParameters);

async function main() {
    // load deployer account
    if (typeof process.env.ETHERSCAN_API_KEY === 'undefined') {
        throw new Error('Etherscan API KEY has not been defined');
    }

    console.log(deployL2OutputParameters);

    try {
        await hre.run(
            'verify:verify',
            {
                address: deployL2OutputParameters.realityETH
            },
        );
    } catch (error) {
        console.log(error);
        expect(error.message.toLowerCase().includes('already verified')).to.be.equal(true);
    }

    try {
        await hre.run(
            'verify:verify',
            {
                address: deployL2OutputParameters.arbitrators[0]
            },
        );
    } catch (error) {
        console.log(error);
        expect(error.message.toLowerCase().includes('already verified')).to.be.equal(true);
    }

    try {

        console.log('verify', deployL2OutputParameters.l2ChainInfo, 'using params', deployParameters.l2BridgeAddress, deployL1OutputParameters.l1GlobalChainInfoPublisher);
        await hre.run(
            'verify:verify',
            {
                address: deployL2OutputParameters.l2ChainInfo
                ,constructorArguments: [
                    deployParameters.l2BridgeAddress,
                    deployL1OutputParameters.l1GlobalChainInfoPublisher
                ]
            },
        );
    } catch (error) {
        console.log(error);
        expect(error.message.toLowerCase().includes('already verified')).to.be.equal(true);
    }

    try {

        await hre.run(
            'verify:verify',
            {
                address: deployL2OutputParameters.l2ForkArbitrator
                ,constructorArguments: [
                    deployL2OutputParameters.realityETH,
                    deployL2OutputParameters.l2ChainInfo,
                    deployL1OutputParameters.l1GlobalForkRequester,
                    deployParameters.forkArbitratorDisputeFee
                ]
            },
        );
    } catch (error) {
        console.log(error);
        expect(error.message.toLowerCase().includes('already verified')).to.be.equal(true);
    }


    try {

        await hre.run(
            'verify:verify',
            {
                address: deployL2OutputParameters.adjudicationFramework
                ,constructorArguments: [
                    deployL2OutputParameters.realityETH,
                    deployParameters.adjudicationFrameworkDisputeFee,
                    deployL2OutputParameters.l2ForkArbitrator,
                    deployL2OutputParameters.arbitrators
                ]
            },
        );
    } catch (error) {
        console.log(error);
        expect(error.message.toLowerCase().includes('already verified')).to.be.equal(true);
    }

    return;

}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

