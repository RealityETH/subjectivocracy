/* eslint-disable no-await-in-loop */
const { time } = require('@nomicfoundation/hardhat-network-helpers');

const { expect } = require('chai');
const { ethers, upgrades } = require('hardhat');
const { Scalar } = require('ffjavascript');
const MerkleTreeBridge = require('@0xpolygonhermez/zkevm-commonjs').MTBridge;

const {
    verifyMerkleProof,
    getLeafValue,
} = require('@0xpolygonhermez/zkevm-commonjs').mtBridgeUtils;

const { contractUtils } = require('@0xpolygonhermez/zkevm-commonjs');

const { generateSolidityInputs } = contractUtils;

const { calculateSnarkInput, calculateBatchHashData, calculateAccInputHash } = contractUtils;

const proofJson = require('./proof.json');
const input = require('./public.json');
const inputJson = require('./input.json');

/**
 * This test simulates the withdrawal process after a fork
 * At chainstart the genesis is similar to the output of the genesis script form this repo
 * In the next block a test account makes a deposit of 10 native tokens (forkonomic tokens)
 * on L2 into the bridge. The transaction was created with the script despoitForkonomicTokenIntoBridgeInL2.js.
 *
 * Then this state advancement with the deposit is verified with a snark proof and submitted. See this PR for the actual state advancement:
 * https://github.com/RealityETH/zkevm-commonjs/pull/2
 *
 * After that the fork is initiated and executed. We then test the withdrawal process.
 *
 */

describe('Simulating first proof after a fork', () => {
    let verifierContract;
    let forkonomicToken;
    let forkableBridge;
    let polygonZkEVMContract;
    let polygonZkEVMGlobalExitRoot;
    let deployer;
    let trustedSequencer;
    let trustedAggregator;
    let admin;

    const genesisRoot = inputJson.oldStateRoot;

    const networkIDMainnet = 0;

    const urlSequencer = 'http://zkevm-json-rpc:8123';
    const { chainID } = inputJson;
    const networkName = 'zkevm';
    const version = '0.0.1';
    const forkID = 6;
    const pendingStateTimeoutDefault = 10;
    const trustedAggregatorTimeoutDefault = 10;
    const arbitrationFee = ethers.utils.parseEther('1');
    const depositBranches = new Array(32).fill(ethers.constants.HashZero);
    let forkingManager;

    beforeEach('Deploy contract', async () => {
        // resetting hardhat to start with an early timestamp, otherwise the first batch may not be initialized with prepared timestamp.
        await ethers.provider.send('hardhat_reset');

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
            '@RealityETH/zkevm-contracts/contracts/verifiers/FflonkVerifier.sol:FflonkVerifier',
        );
        verifierContract = await VerifierRollupHelperFactory.deploy();

        const createChildrenLib = await ethers.getContractFactory('CreateChildren', deployer);
        const createChildrenContract = await createChildrenLib.deploy();
        await createChildrenContract.deployed();
        const createChildrenImplementationAddress = createChildrenContract.address;

        const forkonomicTokenFactory = await ethers.getContractFactory('ForkonomicToken', {
            initializer: false,
            libraries: {
                CreateChildren: createChildrenImplementationAddress,
            },
            constructorArgs: [],
            unsafeAllowLinkedLibraries: true,
        });
        forkonomicToken = await upgrades.deployProxy(
            forkonomicTokenFactory,
            [],
            { initializer: false, unsafeAllowLinkedLibraries: true },
        );

        // deploy global exit root manager
        await upgrades.deployProxyAdmin();

        // deploy global exit root manager
        const polygonZkEVMGlobalExitRootFactory = await ethers.getContractFactory('ForkableExitMock', {
            initializer: false,
            libraries: {
                CreateChildren: createChildrenImplementationAddress,
            },
            constructorArgs: [],
            unsafeAllowLinkedLibraries: true,
        });
        polygonZkEVMGlobalExitRoot = await upgrades.deployProxy(
            polygonZkEVMGlobalExitRootFactory,
            [],
            { initializer: false, unsafeAllowLinkedLibraries: true },
        );

        // deploy PolygonZkEVMBridge
        const bridgeOperationLib = await ethers.getContractFactory('BridgeAssetOperations', deployer);
        const bridgeOperationImplementation = await bridgeOperationLib.deploy();
        await bridgeOperationImplementation.deployed();
        const polygonZkEVMBridgeFactory = await ethers.getContractFactory('ForkableBridge', {
            initializer: false,
            libraries: {
                CreateChildren: createChildrenImplementationAddress,
                BridgeAssetOperations: bridgeOperationImplementation.address,
            },
            constructorArgs: [],
            unsafeAllowLinkedLibraries: true,
        });
        forkableBridge = await upgrades.deployProxy(
            polygonZkEVMBridgeFactory,
            [],
            { initializer: false, unsafeAllowLinkedLibraries: true },
        );

        // deploy forkingManager
        const ForkingManagerFactory = await ethers.getContractFactory('ForkingManager', {
            signer: deployer,
            libraries: { CreateChildren: createChildrenImplementationAddress },
            unsafeAllowLinkedLibraries: true,
            initializer: true,
        });
        forkingManager = await upgrades.deployProxy(
            ForkingManagerFactory,
            [],
            { initializer: false, unsafeAllowLinkedLibraries: true },
        );

        // deploy PolygonZkEVMMock
        const PolygonZkEVMFactory = await ethers.getContractFactory('ForkableZkEVMMock', {
            signer: deployer,
            libraries: { CreateChildren: createChildrenImplementationAddress },
        });
        polygonZkEVMContract = await upgrades.deployProxy(PolygonZkEVMFactory, [], {
            initializer: false,
            unsafeAllowLinkedLibraries: true,
        });

        // deploy chainIdManager
        const chainIdManagerFactory = await ethers.getContractFactory('ChainIdManager', {
            signer: deployer,
        });
        const chainIdManager = await chainIdManagerFactory.deploy(chainID);
        await chainIdManager.deployed();

        // initialize contracts
        const iForkingManager = await ethers.getContractAt('IForkingManager', forkingManager.address);
        await iForkingManager.initialize(
            polygonZkEVMContract.address,
            forkableBridge.address,
            forkonomicToken.address,
            ethers.constants.AddressZero,
            polygonZkEVMGlobalExitRoot.address,
            arbitrationFee,
            chainIdManager.address,
            100,
        );
        const iGlobalExitRoot = await ethers.getContractAt('IForkableGlobalExitRoot', polygonZkEVMGlobalExitRoot.address);
        await iGlobalExitRoot.initialize(
            forkingManager.address,
            ethers.constants.AddressZero,
            polygonZkEVMContract.address,
            forkableBridge.address,
            ethers.constants.HashZero,
            ethers.constants.HashZero,
        );
        const iForkableBridge = await ethers.getContractAt('IForkableBridge', forkableBridge.address);
        await iForkableBridge.initialize(
            forkingManager.address,
            ethers.constants.AddressZero,
            networkIDMainnet,
            polygonZkEVMGlobalExitRoot.address,
            polygonZkEVMContract.address,
            forkonomicToken.address,
            true,
            deployer.address,
            0,
            depositBranches,
        );
        const iForkableZKEVM = await ethers.getContractAt('IForkableZkEVM', polygonZkEVMContract.address);
        await iForkableZKEVM.initialize(
            forkingManager.address,
            ethers.constants.AddressZero,
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
            forkonomicToken.address,
            verifierContract.address,
            forkableBridge.address,
        );
        const iForkableToken = await ethers.getContractAt('IForkonomicToken', forkonomicToken.address);
        iForkableToken.initialize(
            forkingManager.address,
            ethers.constants.AddressZero,
            deployer.address,
            'Forkonomic Token',
            'FORK',
        );

        // fund sequencer address with Matic tokens
        await forkonomicToken.mint(trustedSequencer.address, ethers.utils.parseEther('1000'));
        // await forkonomicToken.transfer(trustedSequencer.address, ethers.utils.parseEther('1000'));
    });

    it('Test verifying of first batch with a withdrawal, fork, do actual withdrawal', async () => {
        const batchesData = inputJson.singleBatchData;
        const batchesNum = batchesData.length;

        // Approve tokens
        const maticAmount = await polygonZkEVMContract.batchFee();
        await expect(
            forkonomicToken.connect(trustedSequencer).approve(polygonZkEVMContract.address, maticAmount.mul(batchesNum)),
        ).to.emit(forkonomicToken, 'Approval');

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
                currentBatchData.timestamp.toString(),
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
                    forkonomicToken.connect(trustedSequencer).approve(polygonZkEVMContract.address, maticAmount.mul(batchesNum)),
                ).to.emit(forkonomicToken, 'Approval');
                await forkonomicToken.transfer(trustedSequencer.address, ethers.utils.parseEther('100'));
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

        // initiate fork
        forkonomicToken.approve(forkingManager.address, arbitrationFee);
        forkonomicToken.mint(deployer.address, arbitrationFee);

        forkingManager.initiateFork({
            disputeContract: forkingManager.address,
            disputeContent: ethers.utils.hexlify(ethers.utils.randomBytes(32)),
            isL1: false,
        });

        await time.increase(3600);
        await forkingManager.executeFork();

        // do withdrawal on child chain
        const [childOneBridgeContract0, childOneBridgeContract1] = await forkableBridge.getChildren();
        const childOneBridge = await ethers.getContractAt('ForkableBridge', childOneBridgeContract0);
        const childTwoBridge = await ethers.getContractAt('ForkableBridge', childOneBridgeContract1);
        const [childGlobalExitRootContract0] = await polygonZkEVMGlobalExitRoot.getChildren();
        const childGlobalExitRoot = await ethers.getContractAt('ForkableGlobalExitRoot', childGlobalExitRootContract0);

        /*
         * inputs from script depositForkonomicTOkenIntoBridgeInL2.js
         * that was used to create the L2 deposit data
         */
        const destinationNetwork = 0;
        const tokenAddress = ethers.constants.AddressZero;
        const destinationAddress = '0x30cEE8B78e4a1cbBfd5Bd7867531bcaBdb00d581';
        const amount = 10;
        const LEAF_TYPE_ASSET = 0;
        const originNetwork = 0;
        const metadata = '0x';
        const metadataHash = ethers.utils.keccak256(metadata);

        // pre compute root merkle tree in Js
        const height = 32;
        const merkleTree = new MerkleTreeBridge(height);
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
        const rootJSRollup = merkleTree.getRoot();

        // check merkle proof
        const merkleProof = merkleTree.getProofTreeByIndex(0);
        const index = 0;
        expect(await childGlobalExitRoot.lastRollupExitRoot(), rootJSRollup);

        // verify merkle proof
        expect(verifyMerkleProof(leafValue, merkleProof, index, rootJSRollup)).to.be.equal(true);

        await forkonomicToken.mint(forkableBridge.address, amount);

        // expects revert because the bridge has no tokens yet
        /*
         * claimAsset(
         *      bytes32[_DEPOSIT_CONTRACT_TREE_DEPTH] calldata smtProof,
         *      uint32 index,
         *      bytes32 mainnetExitRoot,
         *      bytes32 rollupExitRoot,
         *      uint32 originNetwork,
         *      address originTokenAddress,
         *      uint32 destinationNetwork,
         *      address destinationAddress,
         *      uint256 amount,
         *      bytes calldata metadata
         *  )
         */
        expect(childOneBridge.claimAsset(
            merkleProof,
            0,
            ethers.constants.HashZero,
            rootJSRollup,
            originNetwork,
            ethers.constants.AddressZero,
            destinationNetwork,
            destinationAddress,
            amount,
            metadata,
        )).to.be.revertedWith('ERC20: transfer amount exceeds balance');

        await forkableBridge.sendForkonomicTokensToChild(
            amount,
            true,
            false,
        );

        await childOneBridge.claimAsset(
            merkleProof,
            0,
            ethers.constants.HashZero,
            rootJSRollup,
            originNetwork,
            ethers.constants.AddressZero,
            destinationNetwork,
            destinationAddress,
            amount,
            metadata,
        );

        await forkableBridge.sendForkonomicTokensToChild(
            amount,
            false,
            true,
        );

        await childTwoBridge.claimAsset(
            merkleProof,
            0,
            ethers.constants.HashZero,
            rootJSRollup,
            originNetwork,
            ethers.constants.AddressZero,
            destinationNetwork,
            destinationAddress,
            amount,
            metadata,
        );
    });
});
