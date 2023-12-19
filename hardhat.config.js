require('dotenv').config();
require('@nomiclabs/hardhat-waffle');
require('hardhat-gas-reporter');
require('solidity-coverage');
require('@nomiclabs/hardhat-etherscan');
require('@openzeppelin/hardhat-upgrades');
require('hardhat-dependency-compiler');
require('hardhat-preprocessor');
const fs = require('fs');

const DEFAULT_MNEMONIC = 'test test test test test test test test test test test junk';

function getRemappings() {
    return fs
        .readFileSync('remappings.txt', 'utf8')
        .split('\n')
        .filter(Boolean) // remove empty lines
        .map((line) => line.trim().split('='));
}

/*
 * You need to export an object to set up your config
 * Go to https://hardhat.org/config/ to learn more
 */

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
    dependencyCompiler: {
        paths: [
            '@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol',
            '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol',
            '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol',
            '@RealityETH/zkevm-contracts/contracts/deployment/PolygonZkEVMDeployer.sol',
            '@RealityETH/zkevm-contracts/contracts/PolygonZkEVMGlobalExitRootL2.sol',
            '@RealityETH/zkevm-contracts/contracts/PolygonZkEVMTimelock.sol',
            '@RealityETH/zkevm-contracts/contracts/mocks/VerifierRollupHelperMock.sol',
            '@RealityETH/zkevm-contracts/contracts/verifiers/FflonkVerifier.sol',
        ], // ,
    // keep: true
    },
    preprocess: {
        eachLine: (hre) => ({
            transform: (line) => {
                if (line.match(/^\s*import /i)) {
                    for (const [from, to] of getRemappings()) {
                        if (line.includes(from)) {
                            line = line.replace(from, to);
                            break;
                        }
                    }
                }
                return line;
            },
        }),
    },
    paths: {
        sources: './contracts/',
        cache: './cache_hardhat',
        artifacts: './out',
    },
    solidity: {
        compilers: [
            {
                version: '0.8.20',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
            {
                version: '0.6.11',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
            {
                version: '0.5.12',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
            {
                version: '0.5.16',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 999999,
                    },
                },
            },
        ],
    },
    networks: {
        mainnet: {
            url: `https://mainnet.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
            accounts: {
                mnemonic: process.env.MNEMONIC || DEFAULT_MNEMONIC,
                path: "m/44'/60'/0'/0",
                initialIndex: 0,
                count: 20,
            },
        },
        ropsten: {
            url: `https://ropsten.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
            accounts: {
                mnemonic: process.env.MNEMONIC || DEFAULT_MNEMONIC,
                path: "m/44'/60'/0'/0",
                initialIndex: 0,
                count: 20,
            },
        },
        goerli: {
            url: `https://goerli.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
            accounts: {
                mnemonic: process.env.MNEMONIC || DEFAULT_MNEMONIC,
                path: "m/44'/60'/0'/0",
                initialIndex: 0,
                count: 20,
            },
        },
        sepolia: {
            url: `https://sepolia.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
            accounts: {
                mnemonic: process.env.MNEMONIC || DEFAULT_MNEMONIC,
                path: "m/44'/60'/0'/0",
                initialIndex: 0,
                count: 20,
            },
        },
        rinkeby: {
            url: `https://rinkeby.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
            accounts: {
                mnemonic: process.env.MNEMONIC || DEFAULT_MNEMONIC,
                path: "m/44'/60'/0'/0",
                initialIndex: 0,
                count: 20,
            },
        },
        localhost: {
            url: 'http://127.0.0.1:8545',
            accounts: {
                mnemonic: process.env.MNEMONIC || DEFAULT_MNEMONIC,
                path: "m/44'/60'/0'/0",
                initialIndex: 0,
                count: 20,
            },
        },
        hardhat: {
            initialDate: '0',
            allowUnlimitedContractSize: true,
            accounts: {
                mnemonic: process.env.MNEMONIC || DEFAULT_MNEMONIC,
                path: "m/44'/60'/0'/0",
                initialIndex: 0,
                count: 20,
            },
        },
        polygonZKEVMTestnet: {
            url: 'https://rpc.public.zkevm-test.net',
            accounts: {
                mnemonic: process.env.MNEMONIC || DEFAULT_MNEMONIC,
                path: "m/44'/60'/0'/0",
                initialIndex: 0,
                count: 20,
            },
        },
        polygonZKEVMMainnet: {
            url: 'https://zkevm-rpc.com',
            accounts: {
                mnemonic: process.env.MNEMONIC || DEFAULT_MNEMONIC,
                path: "m/44'/60'/0'/0",
                initialIndex: 0,
                count: 20,
            },
        },
        backstopTestnet0: {
            url: "https://rpc.testnet.backstop.technology",
            accounts: {
                mnemonic: process.env.MNEMONIC || DEFAULT_MNEMONIC,
                path: "m/44'/60'/0'/0",
                initialIndex: 0,
                count: 20,
            },
        },
    },
    gasReporter: {
        enabled: !!process.env.REPORT_GAS,
        outputFile: process.env.REPORT_GAS_FILE ? './gas_report.md' : null,
        noColors: !!process.env.REPORT_GAS_FILE,
    },
    etherscan: {
        apiKey: {
            polygonZKEVMTestnet: `${process.env.ETHERSCAN_ZKEVM_API_KEY}`,
            polygonZKEVMMainnet: `${process.env.ETHERSCAN_ZKEVM_API_KEY}`,
            goerli: `${process.env.ETHERSCAN_API_KEY}`,
            sepolia: `${process.env.ETHERSCAN_API_KEY}`,
            mainnet: `${process.env.ETHERSCAN_API_KEY}`,
        },
        zkEVMServices: {
            'backstopTestnet0': {
                bridgeAPIEndpoint: 'https://api.bridge.testnet.backstop.technology'
            }
        },
        customChains: [
            {
                network: 'polygonZKEVMMainnet',
                chainId: 1101,
                urls: {
                    apiURL: 'https://api-zkevm.polygonscan.com/api',
                    browserURL: 'https://zkevm.polygonscan.com/',
                },
            },
            {
                network: 'polygonZKEVMTestnet',
                chainId: 1442,
                urls: {
                    apiURL: 'https://api-testnet-zkevm.polygonscan.com/api',
                    browserURL: 'https://testnet-zkevm.polygonscan.com/',
                },
            },
        ],
    },
};
