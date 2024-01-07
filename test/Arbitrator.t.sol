pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Arbitrator} from "../contracts/lib/reality-eth/Arbitrator.sol";

import {IRealityETH} from "../contracts/lib/reality-eth/interfaces/IRealityETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ArbitratorTest is Test {
    Arbitrator public arb;

    IERC20 internal tokenMock =
        IERC20(0x1234567890123456789012345678901234567890);
    IRealityETH internal realityMock =
        IRealityETH(0x1234567890123456789012345678901234567891);

    function setUp() public {
        arb = new Arbitrator();
        arb.setRealitio(address(realityMock));
    }

    function testSetRealitio() public {
        arb.setRealitio(address(123));
        assertEq(address(arb.realitio()), address(123));
    }

    function testSetDisputeFee() public {
        arb.setDisputeFee(10);
        assertEq(arb.dispute_fee(), 10);
    }

    function testSetCustomDisputeFee() public {
        bytes32 questionId = keccak256(abi.encodePacked("Question 1"));
        arb.setCustomDisputeFee(questionId, 20);
        assertEq(arb.getDisputeFee(questionId), 20);
    }

    function testRequestArbitration() public {
        bytes32 questionId = keccak256(abi.encodePacked("Question 1"));
        arb.setDisputeFee(50);
        vm.mockCall(
            address(realityMock),
            abi.encodeWithSelector(IRealityETH.isFinalized.selector),
            abi.encode(true)
        );

        assertTrue(arb.requestArbitration{value: 50}(questionId, 0));
        assertEq(arb.arbitration_bounties(questionId), 50);
    }

    function testSetMetaData() public {
        arb.setMetaData("Some metadata");
        assertEq(arb.metadata(), "Some metadata");
    }
}
