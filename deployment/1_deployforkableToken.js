/* eslint-disable no-await-in-loop, no-use-before-define, no-lonely-if, import/no-dynamic-require, global-require */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved, no-restricted-syntax */
const path = require('path');
const fs = require('fs');
const { ethers, upgrades } = require('hardhat');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const { expect } = require('chai');
const { deployPolygonZkEVMDeployer } = require('./helpers/deployment-helpers');

const { create2Deployment } = require('./helpers/deployment-helpers');
const deployParameters = require('./deploy_parameters.json');

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
    if (deployParameters.deployerPvtKey) {
        deployer = new ethers.Wallet(deployParameters.deployerPvtKey, currentProvider);
    } else if (process.env.MNEMONIC) {
        deployer = ethers.Wallet.fromMnemonic(process.env.MNEMONIC, 'm/44\'/60\'/0\'/0/0').connect(currentProvider);
    } else {
        [deployer] = (await ethers.getSigners());
    }
    console.log('Deployer: ', deployer.address);

    // Load initialZkEVMDeployerOwner
    const {
        initialZkEVMDeployerOwner,
        salt,
    } = deployParameters;

    if (initialZkEVMDeployerOwner === undefined || initialZkEVMDeployerOwner === '') {
        throw new Error('Missing parameter: initialZkEVMDeployerOwner');
    }

    // Deploy PolygonZkEVMDeployer if is not deployed already using keyless deployment
    const [zkEVMDeployerContract, keylessDeployer] = await deployPolygonZkEVMDeployer(initialZkEVMDeployerOwner, deployer);
    if (keylessDeployer === ethers.constants.AddressZero) {
        console.log('#######################\n');
        console.log('polygonZkEVMDeployer already deployed on: ', zkEVMDeployerContract.address);
    } else {
        console.log('#######################\n');
        console.log('polygonZkEVMDeployer deployed on: ', zkEVMDeployerContract.address);
    }

    expect(deployer.address).to.be.equal(await zkEVMDeployerContract.owner());


    const proxyAdminFactory = await ethers.getContractFactory('ProxyAdmin', deployer);
    const deployTransactionAdmin = (proxyAdminFactory.getDeployTransaction()).data;
    const dataCallAdmin = proxyAdminFactory.interface.encodeFunctionData('transferOwnership', [deployer.address]);
    const [proxyAdminAddress, isProxyAdminDeployed] = await create2Deployment(
        zkEVMDeployerContract,
        salt,
        deployTransactionAdmin,
        dataCallAdmin,
        deployer,
    );

    if(isProxyAdminDeployed) {
        console.log('#######################\n');
        console.log('proxyAdmin deployed on: ', proxyAdminAddress);
    } else {
        console.log('#######################\n');
        console.log('proxyAdmin already deployed on: ', proxyAdminAddress);
    }

    // Deploy implementation PolygonZkEVMBridge
    const createChildrenLib = await ethers.getContractFactory('CreateChildren', deployer);
    const createChildrenLibDeployTransaction = (createChildrenLib.getDeployTransaction()).data;
    const overrideGasLimit = ethers.BigNumber.from(6500000);
    const [createChildrenImplementationAddress] = await create2Deployment(
        zkEVMDeployerContract,
        salt,
        createChildrenLibDeployTransaction,
        null,
        deployer,
        overrideGasLimit,
    );

    console.log('#######################\n');
    console.log('createChildrenImplementation deployed on: ', createChildrenImplementationAddress);

    const forkonomicTokenFactory = await ethers.getContractFactory('ForkonomicToken', {
        signer: deployer,
        libraries: { CreateChildren: createChildrenImplementationAddress },
    });

    forkonomicTokenProxy = await upgrades.deployProxy(forkonomicTokenFactory, [], {
        initializer: false,
        libraries: {
            CreateChildren: createChildrenImplementationAddress,
        },
        constructorArgs: [],
        unsafeAllowLinkedLibraries: true,
    });
    await upgrades.forceImport(forkonomicTokenProxy.address, forkonomicTokenFactory, 'transparent');

    console.log(
        `Token is uninitialized deployed here ${forkonomicTokenProxy.address}. Use it instead of the matic token in the next steps.`,
    );

    // append the new address to the deploy_parameters.json file as the maticTokenAddress, even though we use it as native token
    deployParameters.proxyAdminAddress = proxyAdminAddress;
    deployParameters.maticTokenAddress = forkonomicTokenProxy.address;
    deployParameters.createChildrenImplementationAddress = createChildrenImplementationAddress;
    deployParameters.zkEVMDeployerAddress = zkEVMDeployerContract.address;
    fs.writeFileSync(pathDeployParameters, JSON.stringify(deployParameters, null, 1));
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
