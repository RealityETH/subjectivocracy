/*
 *Deployment loosely based on the upstream 3_deployContracts.ts
 *
 *NB Upstream Polygon administers things with a ProxyAdmin controlled by a Timelock.
 *For simplicity we remove the timelock and have the ProxyAdmin controlled purely by an EOA.
 *Ultimately we will have our own custom system for controlling L1 upgrades.
 *
 *We also remove the deploy_ongoing stuff as the only deployment here is done by create2.
 */

/* eslint-disable no-await-in-loop, no-use-before-define, no-lonely-if, import/no-dynamic-require, global-require */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved, no-restricted-syntax */
const path = require('path');
const fs = require('fs');
const { ethers, upgrades } = require('hardhat');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const { doSpawnInstance} = require('./spawnInstance');

const pathOutputJson = path.join(__dirname, './deploy_output.json');
const generated = require('./deploy_generated.json');

const deployParameters = require('./deploy_parameters.json');
const genesis = require('./genesis.json');

const pathOZUpgradability = path.join(__dirname, `../.openzeppelin/${process.env.HARDHAT_NETWORK}.json`);

async function main() {
    // Check that there's no previous OZ deployment
    if (fs.existsSync(pathOZUpgradability)) {
        throw new Error(`There's upgradability information from previous deployments, it's mandatory to erase them before start a new one, path: ${pathOZUpgradability}`);
    }

    const output = await doSpawnInstance(genesis, deployParameters, generated);
    fs.writeFileSync(pathOutputJson, JSON.stringify(output, null, 1));
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
