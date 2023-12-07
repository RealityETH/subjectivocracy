/* eslint-disable no-await-in-loop, no-use-before-define, no-lonely-if, import/no-dynamic-require, global-require */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved, no-restricted-syntax */
const path = require('path');
const fs = require('fs');
const { expect } = require('chai');
const { ethers, upgrades } = require('hardhat');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

const pathGenesisJson = path.join(__dirname, './genesis.json');
const pathOutputJsonL1System = path.join(__dirname, './deploy_output.json');
const pathOutputJsonL1Applications = path.join(__dirname, './deploy_output_l1_applications.json');
const pathOutputJsonL2Applications = path.join(__dirname, './deploy_output_l2_applications.json');

const pathOngoingDeploymentJson = path.join(__dirname, './deploy_ongoing_l2_applications.json');

const deployParameters = require('./deploy_application_parameters.json');

const delay = ms => new Promise(res => setTimeout(res, ms));

async function main() {
    
    // Check that we already have the L1 settings we need
    if (!fs.existsSync(pathOutputJsonL1Applications)) {
        throw new Error('No l1 application addresses found. Deploy l1 applications first.');
    }
    if (!fs.existsSync(pathOutputJsonL1System)) {
        throw new Error('No system addresses found. Deploy the system first.');
    }

    const l1ApplicationAddresses = require(pathOutputJsonL1Applications);
    const l1SystemAddresses = require(pathOutputJsonL1System);

    const genesisJSON = require(pathGenesisJson);
    const genesisEntries = genesisJSON.genesis;
    let l2BridgeAddress;
    for(const genesisIdx in genesisEntries) {
        const genesisEntry = genesisEntries[genesisIdx];
        if (genesisEntry.contractName == "PolygonZkEVMBridge proxy") {
            l2BridgeAddress = genesisEntry.address;    
            break;
        }
    }
    if (!l2BridgeAddress) {
        throw new Error('Could not find genesis bridge address in genesis.json');
    }

    const {
        l1GlobalChainInfoPublisher,
        l1GlobalForkRequester
    } = l1ApplicationAddresses;

    if (!l1GlobalForkRequester) {
        throw new Error("Missing l1GlobalForkRequester address");
    }
    if (!l1GlobalChainInfoPublisher) {
        throw new Error("Missing l1GlobalChainInfoPublisher address");
    }

    const forkonomicTokenAddress = l1SystemAddresses.maticTokenAddress;

    // Check if there's an ongoing deployment
    let ongoingDeployment = {};
    if (fs.existsSync(pathOngoingDeploymentJson)) {
        ongoingDeployment = require(pathOngoingDeploymentJson);
    }

    /*
     * Check deploy parameters
     * Check that every necessary parameter is fullfilled
     */
    const mandatoryDeploymentParameters = [
        'adjudicationFrameworkDisputeFee',
        'arbitratorDisputeFee',
        'forkArbitratorDisputeFee'
    ];

    for (const parameterName of mandatoryDeploymentParameters) {
        if (deployParameters[parameterName] === undefined || deployParameters[parameterName] === '') {
            throw new Error(`Missing parameter: ${parameterName}`);
        }
    }

    let {
        adjudicationFrameworkDisputeFee,
        forkArbitratorDisputeFee,
        arbitratorDisputeFee,
        arbitratorOwner,
        realityETHAddress, // This is optional, it will be deployed if not supplied
        initialArbitratorAddresses // This can be an empty array
    } = deployParameters;

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
    let deployerBalance = await currentProvider.getBalance(deployer.address);
    console.log('using deployer: ', deployer.address, 'balance is ', deployerBalance.toString());

    if (!realityETHAddress && ongoingDeployment.realityETH) {
        realityETHAddress = ongoingDeployment.realityETH;
    }

    // NB If we deploy then we only do 1 initial arbitrator. But there may be multiple in the config.
    if (initialArbitratorAddresses.length == 0 && ongoingDeployment.initialArbitrator) {
        initialArbitratorAddresses = [ongoingDeployment.initialArbitrator];
    }

    const realityETHFactory = await ethers.getContractFactory('RealityETH_v3_0', {
        signer: deployer,
    });

    let realityETHContract;
    if (!realityETHAddress) {
        realityETHContract = await realityETHFactory.deploy();
        console.log('#######################\n');
        console.log('RealityETH deployed to:', realityETHContract.address);

        // save an ongoing deployment
        ongoingDeployment.realityETH = realityETHContract.address;
        fs.writeFileSync(pathOngoingDeploymentJson, JSON.stringify(ongoingDeployment, null, 1));
    } else {
        realityETHContract = realityETHFactory.attach(realityETHAddress);
        console.log('#######################\n');
        console.log('RealityETH already deployed on: ', realityETHAddress);
    }

    const arbitratorFactory = await ethers.getContractFactory('Arbitrator', {
        signer: deployer,
    });

    if (initialArbitratorAddresses.length == 0) {

        if (!ongoingDeployment.initialArbitrator) {

            const arbitratorContract = await arbitratorFactory.deploy();
            console.log('#######################\n');
            console.log('Arbitrator deployed to:', arbitratorContract.address);

            await arbitratorContract.setRealitio(realityETHContract.address);
            await arbitratorContract.setDisputeFee(arbitratorDisputeFee);

            // save an ongoing deployment
            ongoingDeployment.initialArbitrator = arbitratorContract.address;
            fs.writeFileSync(pathOngoingDeploymentJson, JSON.stringify(ongoingDeployment, null, 1));

            initialArbitratorAddresses = [arbitratorContract.address];

        } else {
            arbitratorContract = arbitratorFactory.attach(initialArbitratorAddresses[0]);
            console.log('#######################\n');
            console.log('Arbitrator(s) already deployed on: ', initialArbitratorAddresses);
            initialArbitratorAddresses = [arbitratorContract.address];
        }
    }


    const l2ChainInfoFactory = await ethers.getContractFactory('L2ChainInfo', {
        signer: deployer,
    });

    let l2ChainInfoContract;
    if (!ongoingDeployment.l2ChainInfo) {
        l2ChainInfoContract = await l2ChainInfoFactory.deploy(
            l2BridgeAddress,
            l1GlobalChainInfoPublisher
        );
        console.log('#######################\n');
        console.log('L2ChainInfo deployed to:', l2ChainInfoContract.address);

        // save an ongoing deployment
        ongoingDeployment.l2ChainInfo = l2ChainInfoContract.address;
        fs.writeFileSync(pathOngoingDeploymentJson, JSON.stringify(ongoingDeployment, null, 1));
    } else {
        l2ChainInfoContract = l2ChainInfoFactory.attach(ongoingDeployment.l2ChainInfo);
        console.log('#######################\n');
        console.log('L2ChainInfo already deployed on: ', ongoingDeployment.l2ChainInfo);
    }


    const l2ForkArbitratorFactory = await ethers.getContractFactory('L2ForkArbitrator', {
        signer: deployer,
    });

    let l2ForkArbitratorContract;
    if (!ongoingDeployment.l2ForkArbitrator) {
        console.log('Deploying L2ForkArbitrator with params', realityETHContract.address, l2ChainInfoContract.address, l1GlobalForkRequester, forkArbitratorDisputeFee);

        l2ForkArbitratorContract = await l2ForkArbitratorFactory.deploy(
            realityETHContract.address,
            l2ChainInfoContract.address,
            l1GlobalForkRequester,
            forkArbitratorDisputeFee
        );
        console.log('#######################\n');
        console.log('L2ForkArbitrator deployed to:', l2ForkArbitratorContract.address);

        // save an ongoing deployment
        ongoingDeployment.l2ForkArbitrator = l2ForkArbitratorContract.address;
        fs.writeFileSync(pathOngoingDeploymentJson, JSON.stringify(ongoingDeployment, null, 1));
    } else {
        l2ForkArbitratorContract = l2ForkArbitratorFactory.attach(ongoingDeployment.l2ForkArbitrator);
        console.log('#######################\n');
        console.log('L2ForkArbitrator already deployed on: ', l2ForkArbitratorContract.address);
    }


    const adjudicationFrameworkFactory = await ethers.getContractFactory('AdjudicationFramework', {
        signer: deployer,
    });

    let adjudicationFrameworkContract;
    if (!ongoingDeployment.adjudicationFramework) {
        console.log('Deploying AdjudicationFramework with params', realityETHContract.address, adjudicationFrameworkDisputeFee, l2ForkArbitratorContract.address, initialArbitratorAddresses);

        adjudicationFrameworkContract = await adjudicationFrameworkFactory.deploy(
            realityETHContract.address,
            adjudicationFrameworkDisputeFee,
            l2ForkArbitratorContract.address,
            initialArbitratorAddresses
        );
        console.log('#######################\n');
        console.log('AdjudicationFramework deployed to:', adjudicationFrameworkContract.address);

        // save an ongoing deployment
        ongoingDeployment.adjudicationFramework = adjudicationFrameworkContract.address;
        fs.writeFileSync(pathOngoingDeploymentJson, JSON.stringify(ongoingDeployment, null, 1));
    } else {
        adjudicationFrameworkContract = adjudicationFrameworkFactory.attach(ongoingDeployment.adjudicationFramework);
        console.log('#######################\n');
        console.log('AdjudicationFramework already deployed on: ', adjudicationFrameworkContract.address);
    }

    /*
    while (!newDeployerBalance || newDeployerBalance.eq(deployerBalance)) {
        newDeployerBalance = await currentProvider.getBalance(deployer.address);
        if (newDeployerBalance.lt(deployerBalance)) {
            break;
        } else {
            console.log('Waiting for RPC node to notice account balance change before trying next deployment');
            await delay(5000);
        }
    }
    console.log('continue using deployer: ', deployer.address, 'balance is now', deployerBalance.toString());
    */

    const outputJson = {
        realityETH: realityETHContract.address,
        arbitrators: initialArbitratorAddresses,
        l2ChainInfo: l2ChainInfoContract.address,
        l2ForkArbitrator: l2ForkArbitratorContract.address,
        adjudicationFramework: adjudicationFrameworkContract.address
    };
    fs.writeFileSync(pathOutputJsonL2Applications, JSON.stringify(outputJson, null, 1));

    // Remove ongoing deployment
    fs.unlinkSync(pathOngoingDeploymentJson);
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
