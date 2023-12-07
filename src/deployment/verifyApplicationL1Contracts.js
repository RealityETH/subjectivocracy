/* eslint-disable import/no-dynamic-require, no-await-in-loop, no-restricted-syntax, guard-for-in */
require('dotenv').config();
const path = require('path');
const hre = require('hardhat');
const { expect } = require('chai');

const pathDeployParameters = path.join(__dirname, './deploy_application_parameters.json');
const pathDeployL1OutputParameters = path.join(__dirname, './deploy_output_l1_applications.json');

const deployParameters = require(pathDeployParameters);
const deployL1OutputParameters = require(pathDeployL1OutputParameters);

async function main() {
    // load deployer account
    if (typeof process.env.ETHERSCAN_API_KEY === 'undefined') {
        throw new Error('Etherscan API KEY has not been defined');
    }

    try {
        await hre.run(
            'verify:verify',
            {
                address: deployL1OutputParameters.l1GlobalChainInfoPublisher
            },
        );
    } catch (error) {
        expect(error.message.toLowerCase().includes('already verified')).to.be.equal(true);
    }

    try {
        await hre.run(
            'verify:verify',
            {
                address: deployL1OutputParameters.l1GlobalForkRequester
            },
        );
    } catch (error) {
        console.log(error);
        expect(error.message.toLowerCase().includes('already verified')).to.be.equal(true);
    }

}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

