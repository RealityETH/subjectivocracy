/* eslint-disable no-console */

const keythereum = require('keythereum');

/*
 * Specify a data directory (optional; defaults to ~/.ethereum)
 * const datadir = '/home/ubuntu/zkevm/zkevm-config';
 * const file = datadir + '/' + 'aggregator.keystore';
 */

const addr = '0x5669c63e3b461cf50696ad0378fe2e66b982d4a7';
// Synchronous
const keyObject = keythereum.importFromFile(addr);

const privateKey = keythereum.recover('password', keyObject);
console.log(privateKey.toString('hex'));
