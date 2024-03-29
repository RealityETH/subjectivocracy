// This deploys the keyless deployer, then uses it deploy implementations with create2

/* eslint-disable no-await-in-loop, no-use-before-define, no-lonely-if, import/no-dynamic-require, global-require */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved, no-restricted-syntax */
const path = require('path');
const fs = require('fs');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

const deployParameters = require('./deploy_parameters.json');
const generatedPath = path.join(__dirname, './deploy_generated.json');

const { doDeployBase } = require('./deployBase');

async function main() {
    const generated = await doDeployBase(deployParameters);
    fs.writeFileSync(generatedPath, JSON.stringify(generated, null, 1));
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
