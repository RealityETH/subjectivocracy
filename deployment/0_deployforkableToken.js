/* eslint-disable no-await-in-loop, no-use-before-define, no-lonely-if, import/no-dynamic-require, global-require */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved, no-restricted-syntax */
const { expect } = require('chai');
const { ethers, upgrades } = require('hardhat');
const path = require('path');
const fs = require('fs');
const hre = require("hardhat");
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const deployParameters = require('./deploy_parameters.json');
const { string } = require('hardhat/internal/core/params/argumentTypes');
const pathDeployParameters = path.join(__dirname, './deploy_parameters.json');

async function main() {

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
     if (process.env.MNEMONIC) {
        deployer = ethers.Wallet.fromMnemonic(process.env.MNEMONIC).connect(currentProvider);
        console.log('Using MNEMONIC deployer with address: ', deployer.address);
    } else {
        [deployer] = (await ethers.getSigners());
    }
    await new Promise(r => setTimeout(r, 2000));
    const forkonomicTokenFactory = await ethers.getContractFactory("ForkonomicToken", deployer);
    const forkonomicToken = await forkonomicTokenFactory.deploy();
    await forkonomicToken.deployed();
    console.log( `Token is uninitialized deployed here
    ${forkonomicToken.address}.
        Use it instead of the matic token in the next steps.
    `);
    const proxyFactory = await ethers.getContractFactory("ERC1967Proxy", deployer);
    const proxy = await proxyFactory.deploy(forkonomicToken.address, ethers.utils.toUtf8Bytes("") ); 
    
      console.log(
        `Token is uninitialized deployed here
        ${proxy.address}.
         Use it instead of the matic token in the next steps.
        `);

    // append the new address to the deploy_parameters.json file as the maticTokenAddress, even though we use it as native token
    const deployParameters = require('./deploy_parameters.json');
    deployParameters.maticTokenAddress = proxy.address;
    fs.writeFileSync(pathDeployParameters, JSON.stringify(deployParameters, null, 1));
    
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
