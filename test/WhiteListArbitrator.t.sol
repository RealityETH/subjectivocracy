pragma solidity ^0.8.10;
import "forge-std/Test.sol";
import "../development/contracts/WhitelistArbitrator.sol";

import "../development/contracts/interfaces/IRealityETH.sol";
import "../development/contracts/RealityETH_ERC20-3.0.sol";
import "../development/contracts/interfaces/IAMB.sol";

contract TestWhitelistArbitrator is Test {
    WhitelistArbitrator whitelistArbitrator;
    RealityETH_ERC20_v3_0 realityETH;
    address payable testAddress = payable(address(0x123));
    address[] initial_arbitrators;
    IAMB internal mockIAMB =
        IAMB(0x1234567890123456789012345678901234567890);
    function beforeEach() public {
    }

    function test_constructor() public {
        realityETH = new RealityETH_ERC20_v3_0();
        initial_arbitrators = [address(0x1), address(0x2)];
        whitelistArbitrator = new WhitelistArbitrator(
            address(realityETH),
            100,
            mockIAMB,
            initial_arbitrators
        );
        assertEq(address(whitelistArbitrator.realityETH()), address(realityETH));
        assertEq(whitelistArbitrator.dispute_fee(), 100);
        assertEq(address(whitelistArbitrator.bridge()), address(mockIAMB));
        assertTrue(whitelistArbitrator.arbitrators(address(0x1)));
        assertTrue(whitelistArbitrator.arbitrators(address(0x2)));
        assertFalse(whitelistArbitrator.arbitrators(address(0x3)));
    }

    function test_requestArbitration() public {
        realityETH = new RealityETH_ERC20_v3_0();
        initial_arbitrators = [address(realityETH), address(testAddress), address(0x1), address(0x2)];
        whitelistArbitrator = new WhitelistArbitrator(
            address(realityETH),
            100,
            mockIAMB,
            initial_arbitrators
        );
        // vm.mockCall(
        //     address(mockIAMB),
        //     abi.encodeWithSelector(mockIAMB.messageSender.selector),
        //     abi.encode(0x00000000000000000000000000000000f0f0F0F0)
        // );
        // vm.prank(address(mockIAMB));
        // realityETH.addArbitrator(address(testAddress));
        // Fund the contract so we can pay for arbitration
        // testAddress.transfer(address(whitelistArbitrator), 200);

        // Before the request, no arbitration is queued
         ( , , uint256 queueArbtirators,, , )=whitelistArbitrator.question_arbitrations("123");
        assertEq( queueArbtirators, 0);

        // Request the arbitration
        vm.deal(testAddress, 1 ether);
        vm.prank(testAddress);
        whitelistArbitrator.requestArbitration{value: 150}("123", 0);
        ( , address payer,uint256 bounty, , ,uint256 last_action_ts )=whitelistArbitrator.question_arbitrations("123");
        // Arbitration should be queued now
        assertEq(bounty, 150);
        assertEq(payer, testAddress);
        assertTrue(last_action_ts > 0);

        // // Verify that the event has been emitted
        // (address sender, ) = vm.warp();
        // (bytes32 question_id, uint256 fee_paid, address requester, uint256 remaining) = assertEvent(
        //     "LogRequestArbitration",
        //     whitelistArbitrator.LogRequestArbitration("123", 150, sender, 50)
        // );
        // assertEq(question_id, "123");
        // assertEq(fee_paid, 150);
        // assertEq(requester, sender);
        // assertEq(remaining, 50);
    
 }
}