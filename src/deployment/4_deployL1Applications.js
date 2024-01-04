/* eslint-disable no-await-in-loop, no-use-before-define, no-lonely-if, import/no-dynamic-require, global-require */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved, no-restricted-syntax */
const path = require('path');
const fs = require('fs');
const { ethers } = require('hardhat');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

const pathOutputJson = path.join(__dirname, './deploy_output_l1_applications.json');
const pathOngoingDeploymentJson = path.join(__dirname, './deploy_ongoing_l1_applications.json');

// const deployParameters = require('./deploy_parameters.json');
const deployParameters = {};

async function main() {
    // Check if there's an ongoing deployment
    let ongoingDeployment = {};
    if (fs.existsSync(pathOngoingDeploymentJson)) {
        ongoingDeployment = require(pathOngoingDeploymentJson);
    }

    /*
     * Check deploy parameters
     * Check that every necessary parameter is fullfilled
     */
    /*
     *const mandatoryDeploymentParameters = [
     *];
     *
     *for (const parameterName of mandatoryDeploymentParameters) {
     *    if (deployParameters[parameterName] === undefined || deployParameters[parameterName] === '') {
     *        throw new Error(`Missing parameter: ${parameterName}`);
     *    }
     *}
     *
     *const {
     *} = deployParameters;
     */

    // Load provider
    let currentProvider = ethers.provider;
    if (deployParameters.multiplierGas || deployParameters.maxFeePerGas) {
        if (process.env.HARDHAT_NETWORK !== 'hardhat') {
            currentProvider = new ethers.providers.JsonRpcProvider(`https://${process.env.HARDHAT_NETWORK}.infura.io/v3/${process.env.INFURA_PROJECT_ID}`);
            if (deployParameters.maxPriorityFeePerGas && deployParameters.maxFeePerGas) {
                console.log(`Hardcoded gas used: MaxPriority${deployParameters.maxPriorityFeePerGas} gwei, MaxFee${deployParameters.maxFeePerGas} gwei`);
                const FEE_DATA = {
                    maxFeePerGas: ethers.utils.parseUnits(deployParameters.maxFeePerGas, 'gwei'),
                    maxPriorityFeePerGas: ethers.utils.parseUnits(deployParameters.maxPriorityFeePerGas, 'gwei'),
                };
                currentProvider.getFeeData = async () => FEE_DATA;
            } else {
                console.log('Multiplier gas used: ', deployParameters.multiplierGas);
                async function overrideFeeData() {
                    const feedata = await ethers.provider.getFeeData();
                    return {
                        maxFeePerGas: feedata.maxFeePerGas.mul(deployParameters.multiplierGas).div(1000),
                        maxPriorityFeePerGas: feedata.maxPriorityFeePerGas.mul(deployParameters.multiplierGas).div(1000),
                    };
                }
                currentProvider.getFeeData = overrideFeeData;
            }
        }
    }

    // Load deployer
    let deployer;
    if (deployParameters.deployerPvtKey) {
        deployer = new ethers.Wallet(deployParameters.deployerPvtKey, currentProvider);
        console.log('Using pvtKey deployer with address: ', deployer.address);
    } else if (process.env.MNEMONIC) {
        deployer = ethers.Wallet.fromMnemonic(process.env.MNEMONIC, 'm/44\'/60\'/0\'/0/0').connect(currentProvider);
        console.log('Using MNEMONIC deployer with address: ', deployer.address);
    } else {
        [deployer] = (await ethers.getSigners());
    }
    const deployerBalance = await currentProvider.getBalance(deployer.address);
    console.log('using deployer: ', deployer.address, 'balance is ', deployerBalance.toString());

    // ../../contracts/L1GlobalChainInfoPublisher.sol  ../../contracts/L1GlobalForkRequester.sol

    const L1GlobalChainInfoPublisherFactory = await ethers.getContractFactory('L1GlobalChainInfoPublisher', {
        signer: deployer,
    });

    if (!ongoingDeployment.l1GlobalChainInfoPublisher) {
        l1GlobalChainInfoPublisherContract = await L1GlobalChainInfoPublisherFactory.deploy();
        console.log('#######################\n');
        console.log('L1GlobalChainInfoPublisherFactory deployed to:', l1GlobalChainInfoPublisherContract.address);

        // save an ongoing deployment
        ongoingDeployment.l1GlobalChainInfoPublisherContract = l1GlobalChainInfoPublisherContract.address;
        fs.writeFileSync(pathOngoingDeploymentJson, JSON.stringify(ongoingDeployment, null, 1));
    } else {
        l1GlobalChainInfoPublisherContract = ChainIdManagerFactory.attach(ongoingDeployment.l1GlobalChainInfoPublisher);
        console.log('#######################\n');
        console.log('L1GlobalChainInfoPublisher already deployed on: ', ongoingDeployment.l1GlobalChainInfoPublisher);
    }

    const L1GlobalForkRequesterFactory = await ethers.getContractFactory('L1GlobalForkRequester', {
        signer: deployer,
    });

    /*
     *let newDeployerBalance;
     *while (!newDeployerBalance || newDeployerBalance.eq(deployerBalance)) {
     *    newDeployerBalance = await currentProvider.getBalance(deployer.address);
     *    if (newDeployerBalance.lt(deployerBalance)) {
     *        break;
     *    } else {
     *        console.log('Waiting for RPC node to notice account balance change before trying next deployment');
     *        await delay(5000);
     *    }
     *}
     *console.log('continue using deployer: ', deployer.address, 'balance is now', deployerBalance.toString());
     */

    if (!ongoingDeployment.l1GlobalForkRequester) {
        l1GlobalForkRequesterContract = await L1GlobalForkRequesterFactory.deploy();
        console.log('#######################\n');
        console.log('L1GlobalForkRequesterFactory deployed to:', l1GlobalForkRequesterContract.address);

        // save an ongoing deployment
        ongoingDeployment.l1GlobalForkRequester = l1GlobalForkRequesterContract.address;
        fs.writeFileSync(pathOngoingDeploymentJson, JSON.stringify(ongoingDeployment, null, 1));
    } else {
        l1GlobalForkRequesterContract = ChainIdManagerFactory.attach(ongoingDeployment.l1GlobalForkRequester);
        console.log('#######################\n');
        console.log('L1GlobalChainInfoPublisherFactory already deployed on: ', ongoingDeployment.l1GlobalForkRequester);
    }

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
