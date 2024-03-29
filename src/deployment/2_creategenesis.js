/* eslint-disable no-await-in-loop, no-use-before-define, no-lonely-if, import/no-dynamic-require */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved, no-restricted-syntax */
const path = require('path');
const fs = require('fs');
const { argv } = require('yargs');
const { expect } = require('chai');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

const deployParametersPath = argv.input ? argv.input : './deploy_parameters.json';
const deployParameters = require(deployParametersPath);

const deployGeneratedPath = argv.input ? argv.input : './deploy_generated.json';
const deployGenerated = require(deployGeneratedPath);

const outPath = argv.out ? argv.out : './genesis.json';
const pathOutputJson = path.join(__dirname, outPath);

const { doCreateGenesis } = require('./createGenesis');

async function main() {
    const genesis = await doCreateGenesis(deployParameters, deployGenerated);
    fs.writeFileSync(pathOutputJson, JSON.stringify(genesis, null, 1));
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});

