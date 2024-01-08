/* eslint-disable no-await-in-loo/
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved */

// Script to run claim for the chain info update
// Based on https://github.com/0xPolygonHermez/code-examples/blob/main/zkevm-nft-bridge-example/scripts/claimMockNFT.js#L34
// Same thing should work for any other claim on L2 except you have to substitute the address of the claimer contract

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });
const { ethers } = require('hardhat');
const hre = require('hardhat');

const network_name = hre.network.name;
const bridgeAPIEndpoint = hre.config.zkEVMServices[network_name].bridgeAPIEndpoint;

const pathGenesisJson = path.join(__dirname, './genesis.json');
const pathOutputJsonL2Applications = path.join(__dirname, './deploy_output_l2_applications.json');

const genesisJSON = require(pathGenesisJson);
const genesisEntries = genesisJSON.genesis;
const l2Applications = require(pathOutputJsonL2Applications);


const merkleProofString = '/merkle-proof';
const getClaimsFromAcc = '/bridges/';

const common = require('./common.js');

async function main() {

    const l2BridgeAddress = common.genesisAddressForContractName("PolygonZkEVMBridge proxy");

    const deployParameters = require('./deploy_application_parameters.json');

    const currentProvider = await common.loadProvider(deployParameters, process.env);
    const deployer = await common.loadDeployer(currentProvider, deployParameters);

    const baseURL = bridgeAPIEndpoint;
    if (!baseURL) {
        throw new Error("Missing baseURL");
    }
    
    const axios = require('axios').create({
        baseURL,
    });

    const l2BridgeFactory = await ethers.getContractFactory('@RealityETH/zkevm-contracts/contracts/inheritedMainContracts/PolygonZkEVMBridge.sol:PolygonZkEVMBridge', deployer);
    const l2BridgeContract = l2BridgeFactory.attach(l2BridgeAddress);

    const sleep = ms => new Promise(r => setTimeout(r, ms));

    function filterClaimable(_depositsArray, _verbose) {

        let claimable = [];
        for (let i = 0; i < _depositsArray.length; i++) {
            const currentDeposit = _depositsArray[i];
            if (!currentDeposit.ready_for_claim) {
                if (_verbose) {
                    console.log('Not ready yet:', currentDeposit.tx_hash);
                }
                continue;
            }
                
            if (currentDeposit.claim_tx_hash != "") {
                if (_verbose) {
                    console.log('already claimed: ', currentDeposit.claim_tx_hash);
                }
                continue;
            }
            claimable.push(currentDeposit);
        }

        return claimable;

    }

    let depositsArray;
    let found = false;
    console.log('Trying claim for contract', l2Applications.l2ChainInfo, 'against bridge', l2BridgeAddress, '...');
    while (!found) {

        const depositAxions = await axios.get(getClaimsFromAcc + l2Applications.l2ChainInfo, { params: { limit: 100, offset: 0 } });
        depositsArray = filterClaimable(depositAxions.data.deposits, true);

        if (depositsArray.length === 0) {
            const secs = 5;
            console.log('No deposits ready to claim yet, retrying in '+secs+' seconds...');
            await sleep(secs*1000);
        } else {
            found = true;
        }
    }

    for (let i = 0; i < depositsArray.length; i++) {
        const currentDeposit = depositsArray[i];
        if (currentDeposit.ready_for_claim) {

            const proofAxios = await axios.get(merkleProofString, {
                params: { deposit_cnt: currentDeposit.deposit_cnt, net_id: currentDeposit.orig_net },
            });

            const { proof } = proofAxios.data;
            const claimTx = await l2BridgeContract.claimMessage(
                proof.merkle_proof,
                currentDeposit.deposit_cnt,
                proof.main_exit_root,
                proof.rollup_exit_root,
                currentDeposit.orig_net,
                currentDeposit.orig_addr,
                currentDeposit.dest_net,
                currentDeposit.dest_addr,
                currentDeposit.amount,
                currentDeposit.metadata,
            );
            console.log('Claim message succesfully sent: ', claimTx.hash);
            await claimTx.wait();
            console.log('Claim message succesfully mined ', claimTx.hash);
        } else {
            console.log('Not ready yet!');
        }
    }
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
