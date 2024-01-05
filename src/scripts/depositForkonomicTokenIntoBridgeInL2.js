/* eslint-disable no-await-in-loop, no-use-before-define, no-lonely-if, import/no-dynamic-require, global-require */
/* eslint-disable no-console, no-inner-declarations, no-undef, import/no-unresolved, no-restricted-syntax */
const path = require('path');
const { ethers } = require('hardhat');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

const MerkleTreeBridge = require('@0xpolygonhermez/zkevm-commonjs').MTBridge;
const {
    // verifyMerkleProof,
    getLeafValue,
} = require('@0xpolygonhermez/zkevm-commonjs').mtBridgeUtils;

/**
 * @dev This script is used to build the tx payload for
 * deposit tokens into the bridge in L2.
 * This is needed for the bridging e2e test.
 */

async function main() {
    const bridgeProxyAddress = '0x139aE7f174a75960DE7050e1b27ADe0c6260f550';
    const bridge = await ethers.getContractAt(
        'contracts/ForkableBridge.sol:ForkableBridge',
        bridgeProxyAddress,
    );
    /*
     * function bridgeAsset(
     *     uint32 destinationNetwork,
     *     address destinationAddress,
     *     uint256 amount,
     *     address token,
     *     bool forceUpdateGlobalExitRoot,
     *     bytes calldata permitData
     * )
     */
    const destinationNetwork = 0;
    const tokenAddress = ethers.constants.AddressZero;
    const destinationAddress = '0x30cEE8B78e4a1cbBfd5Bd7867531bcaBdb00d581';
    const amount = 10;
    const payloadForDeposit = bridge.interface.encodeFunctionData(
        'bridgeAsset',
        [
            destinationNetwork,
            destinationAddress,
            amount, // must be equal to msg.value
            tokenAddress, // since we are sending the native token
            true,
            '0x',
        ],
    );
    console.log('bridgeAsset payload: ', payloadForDeposit);

    const height = 32;
    const merkleTree = new MerkleTreeBridge(height);
    const LEAF_TYPE_ASSET = 0;
    const originNetwork = 0;
    const metadata = '0x';
    const metadataHash = ethers.utils.keccak256(metadata);
    const leafValue = getLeafValue(
        LEAF_TYPE_ASSET,
        originNetwork,
        tokenAddress,
        destinationNetwork,
        destinationAddress,
        amount,
        metadataHash,
    );
    merkleTree.add(leafValue);

    // check merkle root with SC
    const rootJSRollup = merkleTree.getRoot();
    console.log('New updated deposit root: ', rootJSRollup, 'Assuming the deposit tree was empty before');
    // Make sure that the same hash is the output for script in commonjs that calculates the root after applying the tx
}

main().catch((e) => {
    console.error(e);
    process.exit(1);
});
