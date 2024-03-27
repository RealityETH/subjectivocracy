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
        libraries: libraries,
        unsafeAllowLinkedLibraries: unsafeAllowLinkedLibraries
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


async function loadOngoingOrDeployCreate2(create2Deployer, salt, deployer, contractName, ongoingName, args, ongoing, pathOngoing, overrideGasLimit, libraries, unsafeAllowLinkedLibraries, dataCall) {

    const contractFactory = await ethers.getContractFactory(contractName, {
        signer: deployer,
        libraries: libraries,
        unsafeAllowLinkedLibraries: unsafeAllowLinkedLibraries
    });

    let addr;
    if (ongoing[ongoingName]) {
        addr = ongoing[ongoingName];
    }

    let contractInstance;
    let isAlreadyCreated = false;
    if (addr) {
        console.log(ongoingName, 'using existing from ongoing deployment', addr);
    } else {
        const deployTransaction = (contractFactory.getDeployTransaction(...args)).data;
        [addr, isNewlyCreated] = await create2Deployment(create2Deployer, salt, deployTransaction, dataCall, deployer, overrideGasLimit);
        if (isNewlyCreated) {
            console.log(ongoingName, 'deployed with create2', addr);
        } else {
            console.log(ongoingName, 'detected existing create2 deployment, using that', addr);
        }
        // save an ongoing deployment
        ongoing[ongoingName] = addr;
        fs.writeFileSync(pathOngoing, JSON.stringify(ongoing, null, 1));
    } 
    contractInstance = contractFactory.attach(addr);

    return contractInstance;
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
    loadOngoingOrDeploy, loadOngoingOrDeployCreate2, genesisAddressForContractName, predictTransparentProxyAddress
};
