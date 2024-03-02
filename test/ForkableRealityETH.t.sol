pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IRealityETHErrors} from "@reality.eth/contracts/development/contracts/IRealityETHErrors.sol";
import {ForkableRealityETH_ERC20} from "../contracts/ForkableRealityETH_ERC20.sol";
import {ForkonomicToken} from "../contracts/ForkonomicToken.sol";
import {IForkableStructure} from "../contracts/interfaces/IForkableStructure.sol";
import {IForkonomicToken} from "../contracts/interfaces/IForkonomicToken.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {IPolygonZkEVMGlobalExitRoot} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMGlobalExitRoot.sol";
import {IVerifierRollup} from "@RealityETH/zkevm-contracts/contracts/interfaces/IVerifierRollup.sol";
import {L1ForkArbitrator} from "../contracts/L1ForkArbitrator.sol";
import {ForkingManager} from "../contracts/ForkingManager.sol";
import {ChainIdManager} from "../contracts/ChainIdManager.sol";
import {ForkableBridge} from "../contracts/ForkableBridge.sol";
import {ForkableZkEVM} from "../contracts/ForkableZkEVM.sol";
import {ForkableGlobalExitRoot} from "../contracts/ForkableGlobalExitRoot.sol";
import {IPolygonZkEVM} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";

// import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract ForkableRealityETHTest is Test {
    // IERC20Upgradeable public token = IERC20Upgradeable(address(0x987654));

    address public forkmanager;
    address public forkmanager1 = address(0xabc1);
    address public forkmanager2 = address(0xabc2);
    address public forkmanager2a = address(0xabc2a);
    address public forkmanager2b = address(0xabc2b);

    address public parentContract = address(0);
    address public minter = address(0x789);

    address public forkonomicTokenImplementation;
    address public forkonomicToken;

    address public forkableRealityETHImplementation;
    address public forkableRealityETH;

    address public admin = address(0xad);

    bytes32 public forkOverQuestionId;
    bytes32 public importFinalizedUnclaimedQuestionId;
    bytes32 public importFinalizedClaimedQuestionId;
    bytes32 public importUnansweredQuestionId;
    bytes32 public importAnsweredQuestionId;

    address public answerGuyYes1 = address(0xbb0);
    address public answerGuyYes2 = address(0xbb1);
    address public answerGuyNo1 = address(0xbb2);
    address public answerGuyNo2 = address(0xbb3);
    uint256 public answerGuyMintAmount = 1000000;
    bytes32[] public historyHashes;

    address public forkRequester = address(0xc01);
    uint256 public arbitrationFee = 9999999;
    uint64 public initialChainId = 1;

    uint256 public bond1 = 10000;
    uint256 public bond2 = 20000;
    uint256 public bond3 = 40000;

    bytes32 public answer1 = bytes32(uint256(1));
    bytes32 public answer2 = bytes32(uint256(0));
    bytes32 public answer3 = bytes32(uint256(1));

    uint256 public constant UPGRADE_TEMPLATE_ID = 1048576;

    bytes32[32] public depositTree;
    address public hardAssetManger =
        address(0x1234567890123456789012345678901234567891);
    uint32 public networkID = 10;

    uint64 public forkID = 3;
    uint64 public pendingStateTimeout = 123;
    uint64 public trustedAggregatorTimeout = 124235;
    address public trustedSequencer =
        address(0x1234567890123456789012345678901234567899);
    address public trustedAggregator =
        address(0x1234567890123456789012345678901234567898);

    function _initializeZKEVM(
        address _zkevm,
        uint64 _chainId,
        address _bridge,
        address _globalExitRoot
    ) public {
        IPolygonZkEVM.InitializePackedParameters
            memory initializePackedParameters = IPolygonZkEVM
                .InitializePackedParameters({
                    admin: admin,
                    trustedSequencer: trustedSequencer,
                    pendingStateTimeout: pendingStateTimeout,
                    trustedAggregator: trustedAggregator,
                    trustedAggregatorTimeout: trustedAggregatorTimeout,
                    chainID: _chainId,
                    forkID: forkID
                });
        ForkableZkEVM(_zkevm).initialize(
            address(forkmanager),
            address(0x0),
            initializePackedParameters,
            bytes32(
                0x827a9240c96ccb855e4943cc9bc49a50b1e91ba087007441a1ae5f9df8d1c57c
            ),
            "trustedSequencerURL",
            "test network",
            "0.0.1",
            IPolygonZkEVMGlobalExitRoot(_globalExitRoot),
            IERC20Upgradeable(address(forkonomicToken)),
            IVerifierRollup(0x1234567890123456789012345678901234567893),
            IPolygonZkEVMBridge(address(_bridge))
        );
    }

    function setUp() public {
        address bridgeImplementation = address(new ForkableBridge());
        address bridge = address(
            new TransparentUpgradeableProxy(bridgeImplementation, admin, "")
        );

        address forkmanagerImplementation = address(new ForkingManager());
        forkmanager = address(
            new TransparentUpgradeableProxy(
                forkmanagerImplementation,
                admin,
                ""
            )
        );
        forkonomicTokenImplementation = address(new ForkonomicToken());
        forkonomicToken = address(
            new TransparentUpgradeableProxy(
                forkonomicTokenImplementation,
                admin,
                ""
            )
        );

        address zkevmImplementation = address(new ForkableZkEVM());
        address zkevm = address(
            new TransparentUpgradeableProxy(zkevmImplementation, admin, "")
        );

        ForkonomicToken(forkonomicToken).initialize(
            forkmanager,
            parentContract,
            minter,
            "ForkonomicToken",
            "FTK"
        );
        address globalExitRootImplementation = address(
            new ForkableGlobalExitRoot()
        );
        address globalExitRoot = address(
            new TransparentUpgradeableProxy(
                globalExitRootImplementation,
                admin,
                ""
            )
        );
        ForkableGlobalExitRoot(globalExitRoot).initialize(
            address(forkmanager),
            address(0x0),
            address(zkevm),
            bridge,
            bytes32(0),
            bytes32(0)
        );
        ForkableBridge(bridge).initialize(
            address(forkmanager),
            address(0x0),
            networkID,
            ForkableGlobalExitRoot(globalExitRoot),
            address(zkevm),
            address(forkonomicToken),
            false,
            hardAssetManger,
            0,
            depositTree
        );
        address chainIdManager = address(new ChainIdManager(initialChainId));

        _initializeZKEVM(
            zkevm,
            ChainIdManager(chainIdManager).getNextUsableChainId(),
            bridge,
            globalExitRoot
        );

        ForkingManager(forkmanager).initialize(
            address(zkevm),
            address(bridge),
            address(forkonomicToken),
            address(0x0),
            address(globalExitRoot),
            arbitrationFee,
            chainIdManager,
            uint256(60)
        );

        vm.prank(minter);
        IForkonomicToken(forkonomicToken).mint(forkRequester, arbitrationFee);

        forkableRealityETHImplementation = address(
            new ForkableRealityETH_ERC20()
        );
        forkableRealityETH = address(
            ForkableRealityETH_ERC20(
                address(
                    new TransparentUpgradeableProxy(
                        forkableRealityETHImplementation,
                        admin,
                        ""
                    )
                )
            )
        );
        ForkableRealityETH_ERC20(forkableRealityETH).initialize(
            forkmanager,
            address(0),
            forkonomicToken,
            bytes32(0)
        );

        _setupAnswererBalances();
        _setupInitialQuestions();
        _setupHistoryHashes();
    }

    function _setupAnswererBalances() public {
        vm.prank(minter);
        IForkonomicToken(forkonomicToken).mint(
            answerGuyYes1,
            answerGuyMintAmount
        );
        vm.prank(minter);
        IForkonomicToken(forkonomicToken).mint(
            answerGuyYes2,
            answerGuyMintAmount
        );
        vm.prank(minter);
        IForkonomicToken(forkonomicToken).mint(
            answerGuyNo1,
            answerGuyMintAmount
        );
        vm.prank(minter);
        IForkonomicToken(forkonomicToken).mint(
            answerGuyNo2,
            answerGuyMintAmount
        );
    }

    function _setupInitialQuestions() public {
        address l1ForkArbitrator = ForkableRealityETH_ERC20(forkableRealityETH)
            .l1ForkArbitrator();

        vm.prank(forkmanager);
        forkOverQuestionId = ForkableRealityETH_ERC20(forkableRealityETH)
            .askQuestion(
                UPGRADE_TEMPLATE_ID,
                "import me",
                l1ForkArbitrator,
                60,
                0,
                0
            );
        _setupInitialAnswers(forkOverQuestionId);

        // Just a 1 second window so we can finalize this one without finalizing the others
        vm.prank(forkmanager);
        importFinalizedUnclaimedQuestionId = ForkableRealityETH_ERC20(
            forkableRealityETH
        ).askQuestion(
                UPGRADE_TEMPLATE_ID,
                "finalize me but do not claim",
                l1ForkArbitrator,
                1,
                0,
                0
            );
        _setupInitialAnswers(importFinalizedUnclaimedQuestionId);

        vm.prank(forkmanager);
        importFinalizedClaimedQuestionId = ForkableRealityETH_ERC20(
            forkableRealityETH
        ).askQuestion(
                UPGRADE_TEMPLATE_ID,
                "finalize me then claim",
                l1ForkArbitrator,
                1,
                0,
                0
            );
        _setupInitialAnswers(importFinalizedClaimedQuestionId);

        // Push the time forward
        vm.warp(block.timestamp + 2);
        assert(
            ForkableRealityETH_ERC20(forkableRealityETH).isFinalized(
                importFinalizedUnclaimedQuestionId
            )
        );
        assert(
            ForkableRealityETH_ERC20(forkableRealityETH).isFinalized(
                importFinalizedClaimedQuestionId
            )
        );

        assertFalse(
            ForkableRealityETH_ERC20(forkableRealityETH).isFinalized(
                forkOverQuestionId
            )
        );

        vm.prank(forkmanager);
        importUnansweredQuestionId = ForkableRealityETH_ERC20(
            forkableRealityETH
        ).askQuestion(
                UPGRADE_TEMPLATE_ID,
                "do not answer me",
                l1ForkArbitrator,
                60,
                0,
                0
            );

        vm.prank(forkmanager);
        importAnsweredQuestionId = ForkableRealityETH_ERC20(forkableRealityETH)
            .askQuestion(
                UPGRADE_TEMPLATE_ID,
                "answer me but do not finalize",
                l1ForkArbitrator,
                60,
                0,
                0
            );

        _setupInitialAnswers(importAnsweredQuestionId);
    }

    // We use the same set of answers for various different questions
    function _setupInitialAnswers(bytes32 _questionId) public {
        vm.prank(answerGuyYes1);
        ForkonomicToken(forkonomicToken).approve(
            forkableRealityETH,
            uint256(bond1)
        );
        vm.prank(answerGuyYes1);
        ForkableRealityETH_ERC20(forkableRealityETH).submitAnswerERC20(
            _questionId,
            answer1,
            0,
            bond1
        );

        vm.prank(answerGuyNo1);
        ForkonomicToken(forkonomicToken).approve(
            forkableRealityETH,
            uint256(bond2)
        );
        vm.prank(answerGuyNo1);
        ForkableRealityETH_ERC20(forkableRealityETH).submitAnswerERC20(
            _questionId,
            answer2,
            0,
            bond2
        );

        vm.prank(answerGuyYes2);
        ForkonomicToken(forkonomicToken).approve(
            forkableRealityETH,
            uint256(bond3)
        );
        vm.prank(answerGuyYes2);
        ForkableRealityETH_ERC20(forkableRealityETH).submitAnswerERC20(
            _questionId,
            answer3,
            0,
            bond3
        );
    }

    // Record what should have been the history hashes for the answers we hard-coded in _setupInitialAnswers
    function _setupHistoryHashes() internal {
        historyHashes.push(
            keccak256(
                abi.encodePacked(
                    bytes32(0),
                    answer1,
                    bond1,
                    answerGuyYes1,
                    false
                )
            )
        );
        historyHashes.push(
            keccak256(
                abi.encodePacked(
                    historyHashes[0],
                    answer2,
                    bond2,
                    answerGuyNo1,
                    false
                )
            )
        );
        historyHashes.push(
            keccak256(
                abi.encodePacked(
                    historyHashes[1],
                    answer3,
                    bond3,
                    answerGuyYes2,
                    false
                )
            )
        );
    }

    // This does the claim on a finalized question.
    // NB doesn't call withdraw, it just leaves the funds in the balance.
    // TODO: Also test a partway claim
    function _doClaim(
        address _forkableRealityETH,
        bytes32 _questionId
    ) internal {
        uint256 ln = historyHashes.length;
        bytes32[] memory myHistoryHashes = new bytes32[](ln);
        uint256[] memory myBonds = new uint256[](ln);
        address[] memory myAnswerers = new address[](ln);
        bytes32[] memory myAnswers = new bytes32[](ln);

        myHistoryHashes[0] = historyHashes[1];
        myHistoryHashes[1] = historyHashes[0];
        myHistoryHashes[2] = bytes32(0);

        myBonds[0] = bond3;
        myBonds[1] = bond2;
        myBonds[2] = bond1;

        myAnswerers[0] = answerGuyYes2;
        myAnswerers[1] = answerGuyNo1;
        myAnswerers[2] = answerGuyYes1;

        myAnswers[0] = answer3;
        myAnswers[1] = answer2;
        myAnswers[2] = answer1;

        ForkableRealityETH_ERC20(_forkableRealityETH).claimWinnings(
            _questionId,
            myHistoryHashes,
            myAnswerers,
            myBonds,
            myAnswers
        );
    }

    function _forkTokens(
        address _forkonomicToken,
        address _forkmanager1,
        address _forkmanager2
    ) public returns (address, address) {
        address forkonomicToken1;
        address forkonomicToken2;

        address parentForkmanager = ForkonomicToken(_forkonomicToken)
            .forkmanager();

        vm.prank(parentForkmanager);
        // Fork the token like the forkmanager would do in executeFork
        (forkonomicToken1, forkonomicToken2) = IForkonomicToken(
            _forkonomicToken
        ).createChildren();

        vm.prank(parentForkmanager);
        IForkonomicToken(forkonomicToken1).initialize(
            _forkmanager1,
            address(_forkonomicToken),
            parentForkmanager, // TODO: Is this the right thing to set as minter?
            "Child1", //string.concat(IERC20Metadata(address(forkonomicToken)).name(), "0"),
            "Child1" // IERC20Metadata(address(_forkonomicToken)).symbol()
        );
        vm.prank(forkmanager);
        IForkonomicToken(forkonomicToken2).initialize(
            _forkmanager2,
            address(_forkonomicToken),
            parentForkmanager,
            "Child2", // string.concat(IERC20Metadata(address(_forkonomicToken)).name(), "1"),
            "Child2" // IERC20Metadata(address(_forkonomicToken)).symbol()
        );

        return (forkonomicToken1, forkonomicToken2);
    }

    function _forkRealityETH(
        address _forkableRealityETH,
        address _forkonomicToken1,
        address _forkonomicToken2,
        bytes32 _forkOverQuestionId,
        bool _isAlreadyInitialized
    ) internal returns (address, address) {
        address parentForkmanager = ForkableRealityETH_ERC20(
            _forkableRealityETH
        ).forkmanager();

        if (!_isAlreadyInitialized) {
            vm.prank(parentForkmanager);
            ForkableRealityETH_ERC20(_forkableRealityETH).handleInitiateFork();
        }

        vm.prank(parentForkmanager);
        (
            address forkableRealityETH1,
            address forkableRealityETH2
        ) = ForkableRealityETH_ERC20(_forkableRealityETH).createChildren();

        vm.prank(parentForkmanager);
        ForkableRealityETH_ERC20(forkableRealityETH1).initialize(
            ForkonomicToken(_forkonomicToken1).forkmanager(),
            _forkableRealityETH,
            _forkonomicToken1,
            _forkOverQuestionId
        );
        vm.prank(parentForkmanager);
        ForkableRealityETH_ERC20(forkableRealityETH2).initialize(
            ForkonomicToken(_forkonomicToken2).forkmanager(),
            _forkableRealityETH,
            _forkonomicToken2,
            _forkOverQuestionId
        );

        ForkableRealityETH_ERC20(_forkableRealityETH).handleExecuteFork();

        return (forkableRealityETH1, forkableRealityETH2);
    }

    function _testInitialize(address _forkonomicToken) internal {
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH).forkmanager(),
            forkmanager
        );
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH).parentContract(),
            address(0)
        );

        vm.expectRevert("Initializable: contract is already initialized");
        // vm.expectRevert(IForkableStructure.NotInitializing.selector); In future will be this
        ForkableRealityETH_ERC20(forkableRealityETH).initialize(
            forkmanager2,
            forkableRealityETH,
            _forkonomicToken,
            bytes32(0)
        );
    }

    function testInitialize() public {
        _testInitialize(forkonomicToken);
    }

    function testClaim() public {
        _doClaim(forkableRealityETH, importFinalizedClaimedQuestionId);
    }

    function testHandleForkOnlyAfterForking() public {
        // Testing revert if children are not yet created
        vm.prank(forkmanager);
        ForkableRealityETH_ERC20(forkableRealityETH).handleInitiateFork();
        vm.expectRevert(IForkableStructure.OnlyAfterForking.selector);
        ForkableRealityETH_ERC20(forkableRealityETH).handleExecuteFork();
    }

    function _testTemplateCreation(address _forkableRealityETH) internal {
        assertEq(
            ForkableRealityETH_ERC20(_forkableRealityETH).templates(
                UPGRADE_TEMPLATE_ID
            ),
            block.number,
            "Template should have been created at the initial block number"
        );
        assertEq(
            ForkableRealityETH_ERC20(_forkableRealityETH).templates(0),
            0,
            "Standard initial template 0 is not created"
        );
        assertEq(
            ForkableRealityETH_ERC20(_forkableRealityETH).templates(1),
            0,
            "Standard initial template 1 is not created"
        );
    }

    function testInitialRealityETHTemplateCreation() public {
        _testTemplateCreation(forkableRealityETH);
    }

    function testRealityETHTemplateCreationOnFork() public {
        (address _forkonomicToken1, address _forkonomicToken2) = _forkTokens(
            forkonomicToken,
            forkmanager1,
            forkmanager2
        );
        (
            address forkableRealityETH1,
            address forkableRealityETH2
        ) = _forkRealityETH(
                forkableRealityETH,
                _forkonomicToken1,
                _forkonomicToken2,
                forkOverQuestionId,
                false
            );
        _testTemplateCreation(forkableRealityETH1);
        _testTemplateCreation(forkableRealityETH2);
    }

    function testSplitTokenIntoChildTokens() public {
        uint256 initialBalance = ForkonomicToken(forkonomicToken).balanceOf(
            forkableRealityETH
        );
        assert(initialBalance > 0);

        (address _forkonomicToken1, address _forkonomicToken2) = _forkTokens(
            forkonomicToken,
            forkmanager1,
            forkmanager2
        );
        (
            address _forkableRealityETH1,
            address _forkableRealityETH2
        ) = _forkRealityETH(
                forkableRealityETH,
                _forkonomicToken1,
                _forkonomicToken2,
                forkOverQuestionId,
                false
            );

        // The child reality.eth instances should know which token they belong to
        assertEq(
            _forkonomicToken1,
            address(ForkableRealityETH_ERC20(_forkableRealityETH1).token()),
            "child 1 has appropriate token"
        );
        assertEq(
            _forkonomicToken2,
            address(ForkableRealityETH_ERC20(_forkableRealityETH2).token()),
            "child 2 has appropriate token"
        );

        assertEq(
            ForkonomicToken(forkonomicToken).balanceOf(forkableRealityETH),
            0,
            "Parent token balance should be gone"
        );
        assertEq(
            ForkonomicToken(_forkonomicToken1).balanceOf(forkableRealityETH),
            0,
            "Parent reality.eth has nothing in child"
        );
        assertEq(
            ForkonomicToken(_forkonomicToken1).balanceOf(_forkableRealityETH1),
            initialBalance
        );
        assertEq(
            ForkonomicToken(_forkonomicToken2).balanceOf(_forkableRealityETH2),
            initialBalance
        );
    }

    function testInitialQuestionImport() public {
        (address forkonomicToken1, address forkonomicToken2) = _forkTokens(
            forkonomicToken,
            forkmanager1,
            forkmanager2
        );
        (
            address forkableRealityETH1,
            address forkableRealityETH2
        ) = _forkRealityETH(
                forkableRealityETH,
                forkonomicToken1,
                forkonomicToken2,
                forkOverQuestionId,
                false
            );

        // Both the new reality.eths have the question we forked over, and the original one also still has it
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH).getBestAnswer(
                forkOverQuestionId
            ),
            bytes32(uint256(1))
        );
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH1).getBestAnswer(
                forkOverQuestionId
            ),
            bytes32(uint256(1))
        );
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH2).getBestAnswer(
                forkOverQuestionId
            ),
            bytes32(uint256(1))
        );
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH2).getHistoryHash(
                forkOverQuestionId
            ),
            ForkableRealityETH_ERC20(forkableRealityETH).getHistoryHash(
                forkOverQuestionId
            )
        );
        assertNotEq(
            ForkableRealityETH_ERC20(forkableRealityETH2).getHistoryHash(
                forkOverQuestionId
            ),
            bytes32(0)
        );

        // The arbitrator for the imported question will be the arbitrator of the original reality.eth, not the child.
        assertNotEq(
            ForkableRealityETH_ERC20(forkableRealityETH2).getArbitrator(
                forkOverQuestionId
            ),
            ForkableRealityETH_ERC20(forkableRealityETH2).l1ForkArbitrator()
        );
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH2).getArbitrator(
                forkOverQuestionId
            ),
            ForkableRealityETH_ERC20(forkableRealityETH).l1ForkArbitrator()
        );
    }

    function testNoQuestionImport() public {
        // If there's no question to import it should simply complete normally without error
        (address forkonomicToken1, address forkonomicToken2) = _forkTokens(
            forkonomicToken,
            forkmanager1,
            forkmanager2
        );
        _forkRealityETH(
            forkableRealityETH,
            forkonomicToken1,
            forkonomicToken2,
            bytes32(0),
            false
        );
    }

    function testAnsweredQuestionImport() public {
        (address forkonomicToken1, address forkonomicToken2) = _forkTokens(
            forkonomicToken,
            forkmanager1,
            forkmanager2
        );
        (
            address forkableRealityETH1,
            address forkableRealityETH2
        ) = _forkRealityETH(
                forkableRealityETH,
                forkonomicToken1,
                forkonomicToken2,
                forkOverQuestionId,
                false
            );

        // Question not imported until we import it
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH2).getHistoryHash(
                importAnsweredQuestionId
            ),
            bytes32(0)
        );

        // Push the time forward to past the time when the original question would normally finalize
        vm.warp(block.timestamp + 120);

        ForkableRealityETH_ERC20(forkableRealityETH2).importQuestion(
            importAnsweredQuestionId
        );
        assertNotEq(
            ForkableRealityETH_ERC20(forkableRealityETH2).getHistoryHash(
                importAnsweredQuestionId
            ),
            bytes32(0)
        );

        // The arbitrator will be set to the child's arbitrator
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH2).getArbitrator(
                importAnsweredQuestionId
            ),
            ForkableRealityETH_ERC20(forkableRealityETH2).l1ForkArbitrator()
        );

        assertFalse(
            ForkableRealityETH_ERC20(forkableRealityETH2).isFinalized(
                importAnsweredQuestionId
            )
        );
        vm.warp(block.timestamp + 62);
        assertTrue(
            ForkableRealityETH_ERC20(forkableRealityETH2).isFinalized(
                importAnsweredQuestionId
            )
        );

        // Also check the basic import features with the other version
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH1).getHistoryHash(
                importAnsweredQuestionId
            ),
            bytes32(0)
        );

        ForkableRealityETH_ERC20(forkableRealityETH1).importQuestion(
            importAnsweredQuestionId
        );
        assertNotEq(
            ForkableRealityETH_ERC20(forkableRealityETH1).getHistoryHash(
                importAnsweredQuestionId
            ),
            bytes32(0)
        );

        // The arbitrator will be set to the child's arbitrator
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH1).getArbitrator(
                importAnsweredQuestionId
            ),
            ForkableRealityETH_ERC20(forkableRealityETH1).l1ForkArbitrator()
        );
    }

    function testUnansweredQuestionImport() public {
        (address forkonomicToken1, address forkonomicToken2) = _forkTokens(
            forkonomicToken,
            forkmanager1,
            forkmanager2
        );
        (
            address forkableRealityETH1,
            address forkableRealityETH2
        ) = _forkRealityETH(
                forkableRealityETH,
                forkonomicToken1,
                forkonomicToken2,
                forkOverQuestionId,
                false
            );

        // Question not imported until we import it
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH1).getHistoryHash(
                importUnansweredQuestionId
            ),
            bytes32(0)
        );
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH2).getHistoryHash(
                importUnansweredQuestionId
            ),
            bytes32(0)
        );

        // Push the time forward to past the time when the original question would normally finalize if it had been answered
        vm.warp(block.timestamp + 120);
        assertFalse(
            ForkableRealityETH_ERC20(forkableRealityETH2).isFinalized(
                importUnansweredQuestionId
            )
        );

        ForkableRealityETH_ERC20(forkableRealityETH2).importQuestion(
            importUnansweredQuestionId
        );

        // The arbitrator will be set to the child's arbitrator
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH2).getArbitrator(
                importUnansweredQuestionId
            ),
            ForkableRealityETH_ERC20(forkableRealityETH2).l1ForkArbitrator()
        );

        // Even after the timeout elapses again, we're still not finalized
        vm.warp(block.timestamp + 62);
        assertFalse(
            ForkableRealityETH_ERC20(forkableRealityETH2).isFinalized(
                importUnansweredQuestionId
            )
        );
    }

    function testFinalizedUnclaimedQuestionImport() public {
        (address forkonomicToken1, address forkonomicToken2) = _forkTokens(
            forkonomicToken,
            forkmanager1,
            forkmanager2
        );
        (
            address forkableRealityETH1,
            address forkableRealityETH2
        ) = _forkRealityETH(
                forkableRealityETH,
                forkonomicToken1,
                forkonomicToken2,
                forkOverQuestionId,
                false
            );

        // Question not imported until we import it
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH2).getHistoryHash(
                importFinalizedUnclaimedQuestionId
            ),
            bytes32(0)
        );

        // Push the time forward to past the time when the original question would normally finalize
        vm.warp(block.timestamp + 120);

        ForkableRealityETH_ERC20(forkableRealityETH2).importQuestion(
            importFinalizedUnclaimedQuestionId
        );
        assertNotEq(
            ForkableRealityETH_ERC20(forkableRealityETH2).getHistoryHash(
                importFinalizedUnclaimedQuestionId
            ),
            bytes32(0)
        );

        // The arbitrator will be set to the child's arbitrator
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH2).getArbitrator(
                importFinalizedUnclaimedQuestionId
            ),
            ForkableRealityETH_ERC20(forkableRealityETH2).l1ForkArbitrator()
        );

        // Since this was finalized when we did the fork, it's already finalized now.
        assertTrue(
            ForkableRealityETH_ERC20(forkableRealityETH2).isFinalized(
                importFinalizedUnclaimedQuestionId
            )
        );

        // The claim against the parent should fail even though it would have worked before the fork
        vm.expectRevert(IRealityETHErrors.ContractIsFrozen.selector);
        _doClaim(forkableRealityETH, importFinalizedUnclaimedQuestionId);

        _doClaim(forkableRealityETH2, importFinalizedUnclaimedQuestionId);

        // Also check the basic import features with the other version
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH1).getHistoryHash(
                importFinalizedUnclaimedQuestionId
            ),
            bytes32(0)
        );

        ForkableRealityETH_ERC20(forkableRealityETH1).importQuestion(
            importFinalizedUnclaimedQuestionId
        );
        assertNotEq(
            ForkableRealityETH_ERC20(forkableRealityETH1).getHistoryHash(
                importFinalizedUnclaimedQuestionId
            ),
            bytes32(0)
        );

        // The arbitrator will be set to the child's arbitrator
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH1).getArbitrator(
                importFinalizedUnclaimedQuestionId
            ),
            ForkableRealityETH_ERC20(forkableRealityETH1).l1ForkArbitrator()
        );
    }

    function testFinalizedClaimedQuestionImport() public {
        // We start out already finalized on the parent
        assertTrue(
            ForkableRealityETH_ERC20(forkableRealityETH).isFinalized(
                importFinalizedClaimedQuestionId
            )
        );

        assertNotEq(
            ForkableRealityETH_ERC20(forkableRealityETH).getHistoryHash(
                importFinalizedClaimedQuestionId
            ),
            bytes32(0)
        );
        _doClaim(forkableRealityETH, importFinalizedClaimedQuestionId);
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH).getHistoryHash(
                importFinalizedClaimedQuestionId
            ),
            bytes32(0)
        );

        (address _forkonomicToken1, address _forkonomicToken2) = _forkTokens(
            forkonomicToken,
            forkmanager1,
            forkmanager2
        );
        (
            address forkableRealityETH1,
            address forkableRealityETH2
        ) = _forkRealityETH(
                forkableRealityETH,
                _forkonomicToken1,
                _forkonomicToken2,
                forkOverQuestionId,
                false
            );

        // Question not imported until we import it
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH1).getTimeout(
                importFinalizedClaimedQuestionId
            ),
            0
        );
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH2).getTimeout(
                importFinalizedClaimedQuestionId
            ),
            0
        );

        ForkableRealityETH_ERC20(forkableRealityETH2).importQuestion(
            importFinalizedClaimedQuestionId
        );
        assert(
            ForkableRealityETH_ERC20(forkableRealityETH2).getTimeout(
                importFinalizedClaimedQuestionId
            ) > 0
        );
        assertNotEq(
            ForkableRealityETH_ERC20(forkableRealityETH2).getArbitrator(
                importFinalizedClaimedQuestionId
            ),
            address(0)
        );

        // Since this was finalized when we did the fork, it's already finalized now.
        assertTrue(
            ForkableRealityETH_ERC20(forkableRealityETH2).isFinalized(
                importFinalizedClaimedQuestionId
            )
        );

        // The claim will fail as it's already been done
        vm.expectRevert(IRealityETHErrors.ContractIsFrozen.selector);
        _doClaim(forkableRealityETH, importFinalizedClaimedQuestionId);
    }

    function testMoveBalanceToChildren() public {
        // We'll use the claimed question to create an unclaimed balance
        _doClaim(forkableRealityETH, importFinalizedClaimedQuestionId);

        // Too early to do this
        vm.expectRevert();
        ForkableRealityETH_ERC20(forkableRealityETH).moveBalanceToChildren(
            answerGuyYes1
        );

        (address forkonomicToken1, address forkonomicToken2) = _forkTokens(
            forkonomicToken,
            forkmanager1,
            forkmanager2
        );
        (
            address forkableRealityETH1,
            address forkableRealityETH2
        ) = _forkRealityETH(
                forkableRealityETH,
                forkonomicToken1,
                forkonomicToken2,
                forkOverQuestionId,
                false
            );

        // This moves the internal record that we owe the user money.
        // The actual tokens were already transferred in handleExecuteFork()

        // User 1 should have got his bond, then the same again as the takeover fee, minus the claim fee.
        uint256 expectedBalanceYes1 = bond1 + bond1 - (bond1 / 40);
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH).balanceOf(
                answerGuyYes1
            ),
            expectedBalanceYes1
        );

        // Withdraw is banned because we're frozen
        vm.prank(answerGuyYes1);
        vm.expectRevert(IRealityETHErrors.ContractIsFrozen.selector);
        ForkableRealityETH_ERC20(forkableRealityETH).withdraw();

        // No balance on the child yet
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH2).balanceOf(
                answerGuyYes1
            ),
            0
        );

        // Anyone can call this for any beneficiary
        ForkableRealityETH_ERC20(forkableRealityETH).moveBalanceToChildren(
            answerGuyYes1
        );
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH).balanceOf(
                answerGuyYes1
            ),
            0
        );
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH2).balanceOf(
                answerGuyYes1
            ),
            expectedBalanceYes1
        );
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH1).balanceOf(
                answerGuyYes1
            ),
            expectedBalanceYes1
        );
    }

    function testQuestionAskerRestriction() public {
        address l1ForkArbitrator = ForkableRealityETH_ERC20(forkableRealityETH)
            .l1ForkArbitrator();
        vm.expectRevert(IRealityETHErrors.PermittedQuestionerOnly.selector);
        ForkableRealityETH_ERC20(forkableRealityETH).askQuestion(
            UPGRADE_TEMPLATE_ID,
            "questioner restriction question",
            l1ForkArbitrator,
            60,
            0,
            0
        );

        vm.prank(forkmanager);
        ForkableRealityETH_ERC20(forkableRealityETH).askQuestion(
            UPGRADE_TEMPLATE_ID,
            "questioner restriction question",
            l1ForkArbitrator,
            60,
            0,
            0
        );
    }

    function testNextLevelFork() public {
        (address forkonomicToken1, address forkonomicToken2) = _forkTokens(
            forkonomicToken,
            forkmanager1,
            forkmanager2
        );
        (
            address forkableRealityETH1,
            address forkableRealityETH2
        ) = _forkRealityETH(
                forkableRealityETH,
                forkonomicToken1,
                forkonomicToken2,
                forkOverQuestionId,
                false
            );

        // Import a question into both forks
        ForkableRealityETH_ERC20(forkableRealityETH1).importQuestion(
            importFinalizedUnclaimedQuestionId
        );
        ForkableRealityETH_ERC20(forkableRealityETH2).importQuestion(
            importFinalizedUnclaimedQuestionId
        );
        assertNotEq(
            ForkableRealityETH_ERC20(forkableRealityETH2).getHistoryHash(
                importFinalizedUnclaimedQuestionId
            ),
            bytes32(0)
        );

        // We'll do the claim on one fork, then fork again on the other fork
        _doClaim(forkableRealityETH1, importFinalizedUnclaimedQuestionId);

        (address forkonomicToken2a, address forkonomicToken2b) = _forkTokens(
            forkonomicToken2,
            forkmanager2a,
            forkmanager2b
        );

        assertEq(
            IForkonomicToken(forkonomicToken2).parentContract(),
            forkonomicToken
        );
        assertEq(
            IForkonomicToken(forkonomicToken2a).parentContract(),
            forkonomicToken2
        );
        assertEq(
            IForkonomicToken(forkonomicToken2a).forkmanager(),
            forkmanager2a
        );
        assertEq(
            IForkonomicToken(forkonomicToken2b).forkmanager(),
            forkmanager2b
        );
        assertEq(
            IForkonomicToken(forkonomicToken2).forkmanager(),
            ForkableRealityETH_ERC20(forkableRealityETH2).forkmanager()
        );

        (
            address forkableRealityETH2a,
            address forkableRealityETH2b
        ) = _forkRealityETH(
                forkableRealityETH2,
                forkonomicToken2a,
                forkonomicToken2b,
                forkOverQuestionId,
                false
            );

        // The arbitrator will be set to the child's arbitrator
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH1).getArbitrator(
                importFinalizedUnclaimedQuestionId
            ),
            ForkableRealityETH_ERC20(forkableRealityETH1).l1ForkArbitrator()
        );
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH2).getArbitrator(
                importFinalizedUnclaimedQuestionId
            ),
            ForkableRealityETH_ERC20(forkableRealityETH2).l1ForkArbitrator()
        );

        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH2a).getArbitrator(
                importFinalizedUnclaimedQuestionId
            ),
            address(0)
        );
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH2b).getArbitrator(
                importFinalizedUnclaimedQuestionId
            ),
            address(0)
        );

        ForkableRealityETH_ERC20(forkableRealityETH2a).importQuestion(
            importFinalizedUnclaimedQuestionId
        );
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH2a).getArbitrator(
                importFinalizedUnclaimedQuestionId
            ),
            ForkableRealityETH_ERC20(forkableRealityETH2a).l1ForkArbitrator()
        );

        // Since this was finalized when we did the fork, it's already finalized now.
        assertTrue(
            ForkableRealityETH_ERC20(forkableRealityETH).isFinalized(
                importFinalizedUnclaimedQuestionId
            )
        );
        assertTrue(
            ForkableRealityETH_ERC20(forkableRealityETH2).isFinalized(
                importFinalizedUnclaimedQuestionId
            )
        );
        assertTrue(
            ForkableRealityETH_ERC20(forkableRealityETH2a).isFinalized(
                importFinalizedUnclaimedQuestionId
            )
        );
    }

    function _setupArbitrationRequest(
        address _forkableRealityETH,
        address _forkRequester,
        bytes32 _forkOverQuestionId,
        address _forkmanager
    ) internal returns (address) {
        L1ForkArbitrator l1ForkArbitrator = L1ForkArbitrator(
            ForkableRealityETH_ERC20(forkableRealityETH).l1ForkArbitrator()
        );
        assertEq(ForkableRealityETH_ERC20(_forkableRealityETH).freezeTs(), 0);
        ForkonomicToken token = ForkonomicToken(
            address(ForkableRealityETH_ERC20(forkableRealityETH).token())
        );
        uint256 fee = l1ForkArbitrator.getDisputeFee(bytes32(0));
        vm.prank(_forkRequester);
        token.approve(address(l1ForkArbitrator), fee);
        vm.prank(_forkRequester);
        l1ForkArbitrator.requestArbitration(_forkOverQuestionId, 0);
        vm.prank(_forkmanager);
        // TODO: The add code to the ForkingManager to call this in `initiateFork` which should be called by `requestArbitration`
        // Alternatively change the flow so that someone else can do this. See #243
        ForkableRealityETH_ERC20(forkableRealityETH).handleInitiateFork();
        return address(l1ForkArbitrator);
    }

    function testRequestArbitration() public {
        L1ForkArbitrator l1ForkArbitrator = L1ForkArbitrator(
            _setupArbitrationRequest(
                forkableRealityETH,
                forkRequester,
                forkOverQuestionId,
                forkmanager
            )
        );
        assertEq(l1ForkArbitrator.payer(), forkRequester);
        assertEq(l1ForkArbitrator.arbitratingQuestionId(), forkOverQuestionId);
        assert(ForkableRealityETH_ERC20(forkableRealityETH).freezeTs() > 0);
        assert(
            ForkingManager(forkmanager).executionTimeForProposal() >
                block.timestamp
        );
    }

    function testPostForkHandling() public {
        L1ForkArbitrator l1ForkArbitrator = L1ForkArbitrator(
            _setupArbitrationRequest(
                forkableRealityETH,
                forkRequester,
                forkOverQuestionId,
                forkmanager
            )
        );
        vm.warp(ForkingManager(forkmanager).executionTimeForProposal() + 1);
        address originalToken = ForkingManager(forkmanager).forkonomicToken();
        uint256 originalBalance = IForkonomicToken(originalToken).balanceOf(
            forkableRealityETH
        );
        assert(originalBalance > 0);

        ForkingManager(forkmanager).executeFork();
        vm.prank(forkmanager);
        (address childForkmanager1, address childForkmanager2) = ForkingManager(
            forkmanager
        ).getChildren();
        address childToken1 = ForkingManager(childForkmanager1)
            .forkonomicToken();
        address childToken2 = ForkingManager(childForkmanager2)
            .forkonomicToken();

        // TODO: Add this logic to executeFork() so we don't need to call it here.
        // This will call forkableRealityETH.handleExecuteFork();
        (
            address forkableRealityETH2a,
            address forkableRealityETH2b
        ) = _forkRealityETH(
                forkableRealityETH,
                childToken1,
                childToken2,
                forkOverQuestionId,
                true
            );
        assertEq(
            IForkonomicToken(originalToken).balanceOf(forkableRealityETH),
            0
        );
        assertEq(
            IForkonomicToken(childToken1).balanceOf(forkableRealityETH2a),
            originalBalance
        );
        assertEq(
            IForkonomicToken(childToken2).balanceOf(forkableRealityETH2b),
            originalBalance
        );

        vm.expectRevert(IRealityETHErrors.QuestionMustBeFinalized.selector);
        ForkableRealityETH_ERC20(forkableRealityETH).resultFor(
            forkOverQuestionId
        );
        vm.expectRevert(IRealityETHErrors.QuestionMustBeFinalized.selector);
        ForkableRealityETH_ERC20(forkableRealityETH2a).resultFor(
            forkOverQuestionId
        );
        vm.expectRevert(IRealityETHErrors.QuestionMustBeFinalized.selector);
        ForkableRealityETH_ERC20(forkableRealityETH2b).resultFor(
            forkOverQuestionId
        );

        l1ForkArbitrator.settleChildren(
            historyHashes[historyHashes.length - 2],
            answer3,
            answerGuyYes2
        );
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH2a).resultFor(
                forkOverQuestionId
            ),
            bytes32(uint256(0))
        );
        assertEq(
            ForkableRealityETH_ERC20(forkableRealityETH2b).resultFor(
                forkOverQuestionId
            ),
            bytes32(uint256(1))
        );
    }
}
