/* eslint-disable no-await-in-loop, no-use-before-define, no-lonely-if, import/no-dynamic-require, global-require */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved, no-restricted-syntax */
const path = require('path');
const fs = require('fs');
const { ethers } = require('hardhat');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

const pathGenesisJson = path.join(__dirname, './deployment/genesis.json');
const { create2Deployment } = require('./helpers/deployment-helpers');

async function loadOngoingOrDeploy(deployer, contractName, ongoingName, args, ongoing, pathOngoing, externallyDeployedAddress, libraries, unsafeAllowLinkedLibraries) {
    const contractFactory = await ethers.getContractFactory(contractName, {
        signer: deployer,
        libraries,
        unsafeAllowLinkedLibraries,
    });

    let existingAddress;
    if (externallyDeployedAddress) {
        existingAddress = externallyDeployedAddress;
    } else if (ongoing[ongoingName]) {
        existingAddress = ongoing[ongoingName];
    }

    let contractInstance;
    if (!existingAddress) {
        contractInstance = await contractFactory.deploy(...args);
        await contractInstance.deployed();
        console.log(ongoingName, 'deployed to:', contractInstance.address);

        // save an ongoing deployment
        ongoing[ongoingName] = contractInstance.address;
        fs.writeFileSync(pathOngoing, JSON.stringify(ongoing, null, 1));
    } else {
        contractInstance = contractFactory.attach(existingAddress);
        console.log(ongoingName, 'already deployed on: ', existingAddress);
    }

    return contractInstance;
}

async function create2Deploy(create2Deployer, salt, deployer, contractName, args, gasLimit, libraries, unsafeAllowLinkedLibraries, dataCall) {
    const contractFactory = await ethers.getContractFactory(contractName, {
        signer: deployer,
        libraries,
        unsafeAllowLinkedLibraries,
    });

    let addr;

    const displayName = contractName.replace(/^.*[\\/]/, '');

    if (addr) {
        console.log(displayName, 'using existing from ongoing deployment', addr);
    } else {
        const deployTransaction = (contractFactory.getDeployTransaction(...args)).data;
        [addr, isNewlyCreated] = await create2Deployment(create2Deployer, salt, deployTransaction, dataCall, deployer, gasLimit);
        if (isNewlyCreated) {
            console.log(displayName, 'deployed with create2', addr);
        } else {
            console.log(displayName, 'detected existing create2 deployment, using that', addr);
        }
    }
    return addr;
}

function genesisAddressForContractName(contractName) {
    const genesisJSON = require(pathGenesisJson);
    const genesisEntries = genesisJSON.genesis;
    for (const [, genesisEntry] of Object.entries(genesisEntries)) {
        if (genesisEntry.contractName === contractName) {
            return genesisEntry.address;
        }
    }
    throw new Error(`Could not find genesis entry ${contractName}`);
}

async function predictTransparentProxyAddress(deployingForkingManagerImplementationAddress, implementationAddress, admin, sender) {
    const transparentProxyFactory = await ethers.getContractFactory('@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy');
    const initializeEmptyDataProxy = '0x';
    const deployTransactionProxy = (transparentProxyFactory.getDeployTransaction(
        implementationAddress,
        admin, // proxyAdminAddress,
        initializeEmptyDataProxy,
    )).data;
    const hashInitCode = ethers.utils.solidityKeccak256(['bytes'], [deployTransactionProxy]);
    const salt = ethers.utils.solidityKeccak256(['address'], [sender]);
    return ethers.utils.getCreate2Address(deployingForkingManagerImplementationAddress, salt, hashInitCode);
}

module.exports = {
    loadOngoingOrDeploy, create2Deploy, genesisAddressForContractName, predictTransparentProxyAddress,
};
