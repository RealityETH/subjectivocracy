// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

import {IBridgeMessageReceiver} from "@RealityETH/zkevm-contracts/contracts/interfaces/IBridgeMessageReceiver.sol";

contract MockPolygonZkEVMBridge {
    function bridgeMessage(
        uint32 destinationNetwork,
        address destinationAddress,
        bool forceUpdateGlobalExitRoot,
        bytes calldata metadata
    ) public payable virtual {}

    function bridgeAsset(
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        address token,
        bool forceUpdateGlobalExitRoot,
        bytes calldata permitData
    ) public payable {}

    receive() external payable {}

    function fakeClaimMessage(
        address originAddress,
        uint32 originNetwork,
        address destinationAddress,
        bytes memory metadata,
        uint256 amount
    ) external {
        /* solhint-disable avoid-low-level-calls */
        (bool success, ) = destinationAddress.call{value: amount}(
            abi.encodeCall(
                IBridgeMessageReceiver.onMessageReceived,
                (originAddress, originNetwork, metadata)
            )
        );
        /* solhint-disable custom-errors */
        require(success, "Call failed");
    }
}
