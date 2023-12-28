/* eslint-disable no-await-in-loop */

const { expect } = require('chai');
const { ethers, upgrades } = require('hardhat');
const { Scalar } = require('ffjavascript');

const { contractUtils } = require('@0xpolygonhermez/zkevm-commonjs');

const { generateSolidityInputs } = contractUtils;

const { calculateSnarkInput, calculateBatchHashData, calculateAccInputHash } = contractUtils;

const proofJson = require('./proof.json');
const input = require('./public.json');
const inputJson = require('./input.json');

/**
 * This test simulates the first proof after a fork
 * The stateRoot and the globalExitRoot of the old state was calculated with an old chainID: 1000
 * The new chainID is 1001. The test shows that the newly generated proof is valid
 * on the real verifier contract. To show this a polygonZkEVM contract is set up
 * with the old state root, as it is done in a fork scenario via forkingManager contract.
 * After this a new batch is sequenced and the proof is verified.
 *
 * The old state root was generated with the zkevm state tool from common-js. See this fork:
 * https://github.com/RealityETH/zkevm-commonjs/pull/1/files
 * and especially these lines:
 * https://github.com/RealityETH/zkevm-commonjs/blob/main/test/processor-forking.test.js#L148-L154
 * It took the genesis state from our deployment script and the first two transactions are
 * some transfers on the chain.
 *
 * Note that we run this "deterministic test" without a fork introduced by the forkingManager,
 * as this would require us to generate a proof for specific inputs (stateHash, globalExitRoot, etc.) 
 * that would require us to prover each new test-run (unless one is able to set up the test perfectly deterministic as well).
 * This would be additional work and is not necessary to verify that we can
 * continue to use the old state root and globalExitRoot with a new chainID - as it is done in this test
 */

describe('Simulating first proof after a fork', () => {
    let verifierContract;
    let maticTokenContract;
    let polygonZkEVMBridgeContract;
    let polygonZkEVMContract;
    let polygonZkEVMGlobalExitRoot;
    let deployer;
    let trustedSequencer;
    let trustedAggregator;
    let admin;

    const maticTokenName = 'Fork Token';
    const maticTokenSymbol = 'FORK';
    const maticTokenInitialBalance = ethers.utils.parseEther('20000000');

    const genesisRoot = inputJson.oldStateRoot;

    const networkIDMainnet = 0;

    const urlSequencer = 'http://zkevm-json-rpc:8123';
    const { chainID } = inputJson;
    const networkName = 'zkevm';
    const version = '0.0.1';
    const forkID = 6;
    const pendingStateTimeoutDefault = 10;
    const trustedAggregatorTimeoutDefault = 10;
    const depositBranches = new Array(32).fill(ethers.constants.HashZero);

    beforeEach('Deploy contract', async () => {
        upgrades.silenceWarnings();

        // load signers
        [deployer, trustedAggregator, admin] = await ethers.getSigners();

        /*
         * fund trustedAggregator address
         * Could be different address theortically but for now it's fine
         */
        const trustedSequencerAddress = inputJson.singleBatchData[0].sequencerAddr;
        await ethers.provider.send('hardhat_impersonateAccount', [trustedSequencerAddress]);
        trustedSequencer = await ethers.getSigner(trustedSequencerAddress);
        await deployer.sendTransaction({
            to: trustedSequencerAddress,
            value: ethers.utils.parseEther('4'),
        });

        // deploy real verifier
        const VerifierRollupHelperFactory = await ethers.getContractFactory(
            'FflonkVerifier',
        );
        verifierContract = await VerifierRollupHelperFactory.deploy();

        // deploy MATIC
        const maticTokenFactory = await ethers.getContractFactory('ERC20PermitMock');
        maticTokenContract = await maticTokenFactory.deploy(
            maticTokenName,
            maticTokenSymbol,
            deployer.address,
            maticTokenInitialBalance,
        );
        await maticTokenContract.deployed();

        // deploy global exit root manager
        await upgrades.deployProxyAdmin();

        // deploy global exit root manager
        const polygonZkEVMGlobalExitRootFactory = await ethers.getContractFactory('PolygonZkEVMGlobalExitRootMock');
        polygonZkEVMGlobalExitRoot = await upgrades.deployProxy(polygonZkEVMGlobalExitRootFactory, [], { initializer: false });

        // deploy PolygonZkEVMBridge
        const polygonZkEVMBridgeFactory = await ethers.getContractFactory('PolygonZkEVMBridgeWrapper');
        polygonZkEVMBridgeContract = await upgrades.deployProxy(polygonZkEVMBridgeFactory, [], { initializer: false });

        // deploy PolygonZkEVMMock
        const PolygonZkEVMFactory = await ethers.getContractFactory('PolygonZkEVMMock');
        polygonZkEVMContract = await upgrades.deployProxy(PolygonZkEVMFactory, [], {
            initializer: false,
        });

        // initialize contracts
        await polygonZkEVMGlobalExitRoot.initialize(polygonZkEVMContract.address, polygonZkEVMBridgeContract.address);
        await polygonZkEVMBridgeContract.initialize(
            networkIDMainnet,
            polygonZkEVMGlobalExitRoot.address,
            polygonZkEVMContract.address,
            maticTokenContract.address,
            true,
            0,
            depositBranches,
        );
        await polygonZkEVMContract.initialize(
            {
                admin: admin.address,
                trustedSequencer: trustedSequencer.address,
                pendingStateTimeout: pendingStateTimeoutDefault,
                trustedAggregator: trustedAggregator.address,
                trustedAggregatorTimeout: trustedAggregatorTimeoutDefault,
                chainID,
                forkID,
            },
            genesisRoot,
            urlSequencer,
            networkName,
            version,
            polygonZkEVMGlobalExitRoot.address,
            maticTokenContract.address,
            verifierContract.address,
            polygonZkEVMBridgeContract.address,
        );

        // fund sequencer address with Matic tokens
        await maticTokenContract.transfer(trustedSequencer.address, ethers.utils.parseEther('1000'));
    });

    it('Test verifying of first batch after a fork', async () => {
        const batchesData = inputJson.singleBatchData;
        const batchesNum = batchesData.length;

        // Approve tokens
        const maticAmount = await polygonZkEVMContract.batchFee();
        await expect(
            maticTokenContract.connect(trustedSequencer).approve(polygonZkEVMContract.address, maticAmount.mul(batchesNum)),
        ).to.emit(maticTokenContract, 'Approval');

        // prepare PolygonZkEVMMock
        await polygonZkEVMContract.setVerifiedBatch(inputJson.oldNumBatch);
        await polygonZkEVMContract.setSequencedBatch(inputJson.oldNumBatch);
        const lastTimestamp = batchesData[batchesNum - 1].timestamp;
        await ethers.provider.send('evm_setNextBlockTimestamp', [lastTimestamp]);

        for (let i = 0; i < batchesNum; i++) {
            // set timestamp for the sendBatch call
            const currentBatchData = batchesData[i];

            const currentSequence = {
                transactions: currentBatchData.batchL2Data,
                globalExitRoot: currentBatchData.globalExitRoot,
                timestamp: currentBatchData.timestamp,
                minForcedTimestamp: 0,
            };

            const batchAccInputHashJs = calculateAccInputHash(
                currentBatchData.oldAccInputHash,
                calculateBatchHashData(currentBatchData.batchL2Data),
                currentBatchData.globalExitRoot,
                currentBatchData.timestamp,
                currentBatchData.sequencerAddr, // fix
            );
            expect(batchAccInputHashJs).to.be.eq(currentBatchData.newAccInputHash);

            // prepare globalExitRoot
            const randomTimestamp = 1001;
            const { globalExitRoot } = batchesData[0];
            await polygonZkEVMGlobalExitRoot.setGlobalExitRoot(globalExitRoot, randomTimestamp);

            const lastBatchSequenced = await polygonZkEVMContract.lastBatchSequenced();

            // check trusted sequencer
            const trustedSequencerAddress = inputJson.singleBatchData[i].sequencerAddr;
            if (trustedSequencer.address !== trustedSequencerAddress) {
                await polygonZkEVMContract.connect(admin).setTrustedSequencer(trustedSequencerAddress);
                await ethers.provider.send('hardhat_impersonateAccount', [trustedSequencerAddress]);
                trustedSequencer = await ethers.getSigner(trustedSequencerAddress);
                await deployer.sendTransaction({
                    to: trustedSequencerAddress,
                    value: ethers.utils.parseEther('4'),
                });
                await expect(
                    maticTokenContract.connect(trustedSequencer).approve(polygonZkEVMContract.address, maticAmount.mul(batchesNum)),
                ).to.emit(maticTokenContract, 'Approval');
                await maticTokenContract.transfer(trustedSequencer.address, ethers.utils.parseEther('100'));
            }

            // Sequence Batches
            await expect(polygonZkEVMContract.connect(trustedSequencer).sequenceBatches([currentSequence], trustedSequencer.address))
                .to.emit(polygonZkEVMContract, 'SequenceBatches')
                .withArgs(Number(lastBatchSequenced) + 1);
        }

        // Set state and exit root
        await polygonZkEVMContract.setStateRoot(inputJson.oldStateRoot, inputJson.oldNumBatch);

        const { aggregatorAddress } = inputJson;
        await ethers.provider.send('hardhat_impersonateAccount', [aggregatorAddress]);
        const aggregator = await ethers.getSigner(aggregatorAddress);
        await deployer.sendTransaction({
            to: aggregatorAddress,
            value: ethers.utils.parseEther('4'),
        });
        await polygonZkEVMContract.connect(admin).setTrustedAggregator(aggregatorAddress);

        const batchAccInputHash = (await polygonZkEVMContract.sequencedBatches(inputJson.newNumBatch)).accInputHash;
        expect(batchAccInputHash).to.be.equal(inputJson.newAccInputHash);

        const proof = generateSolidityInputs(proofJson);

        // Verify snark input
        const circuitInputStarkJS = await calculateSnarkInput(
            inputJson.oldStateRoot,
            inputJson.newStateRoot,
            inputJson.newLocalExitRoot,
            inputJson.oldAccInputHash,
            inputJson.newAccInputHash,
            inputJson.oldNumBatch,
            inputJson.newNumBatch,
            inputJson.chainID,
            inputJson.aggregatorAddress,
            forkID,
        );

        expect(circuitInputStarkJS).to.be.eq(Scalar.e(input[0]));

        // aggregator forge the batch
        const { newLocalExitRoot } = inputJson;
        const { newStateRoot } = inputJson;
        const { oldNumBatch } = inputJson;
        const { newNumBatch } = inputJson;
        const pendingStateNum = 0;

        // Verify batch
        await expect(
            polygonZkEVMContract.connect(aggregator).verifyBatchesTrustedAggregator(
                pendingStateNum,
                oldNumBatch,
                newNumBatch,
                newLocalExitRoot,
                newStateRoot,
                Array.from(Array(24)).fill('0x0e7073c1e73dfb716c35623b741e4ccfc6290d943f3df60377ad8799373ae439'), // this is arbitrary data
            ),
        ).to.be.revertedWith('InvalidProof');
        await expect(
            polygonZkEVMContract.connect(aggregator).verifyBatchesTrustedAggregator(
                pendingStateNum,
                oldNumBatch,
                newNumBatch,
                newLocalExitRoot,
                newStateRoot,
                proof,
            ),
        ).to.emit(polygonZkEVMContract, 'VerifyBatchesTrustedAggregator')
            .withArgs(newNumBatch, newStateRoot, aggregator.address);
    });
});
