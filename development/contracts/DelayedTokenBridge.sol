// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.17;

import "./interfaces/IERC20Mint.sol";
import "./ForkManager.sol";

contract DelayedTokenBridge {
    IERC20Mint token;

    ForkManager forkmanager;
    IAMB bridge;
    address l2contract;

    mapping(bytes32 => uint256) queuedMessages;

    uint256 constant DELAY_SECS = 86400;

    constructor(IERC20Mint _token, address _l2contract) {
        token = _token;
        l2contract = _l2contract;
    }

    // You can send via whatever bridges you like, if they're shady it's your problem
    function sendToL2(uint256 _amount, address[] memory _bridges) external {
        require(
            token.transferFrom(msg.sender, address(this), _amount),
            "Transfer failed"
        );
        for (uint256 i = 0; i < _bridges.length; i++) {
            bytes memory data = abi.encodeWithSelector(
                IERC20Mint(l2contract).mint.selector,
                msg.sender,
                _amount
            );
            IAMB(_bridges[i]).requireToPassMessage(l2contract, data, 0);
        }
    }

    // Queue a message from L2
    // Once the delay has passed you'll be able to unlock it, provided the bridge is still current
    // If we're in a forking state, you may need the same confirmation from multiple bridges
    function receiveFromL2(address _to, uint256 _amount) external {
        // We never want a message if the bridge says it comes from something other than the home proxy
        require(
            IAMB(msg.sender).messageSender() != l2contract,
            "Wrong home proxy"
        );

        bytes32 messageID = keccak256(
            abi.encodePacked(_to, _amount, msg.sender, block.timestamp)
        );
        queuedMessages[messageID] = queuedMessages[messageID] + 1;
    }

    // Process a message that was previously queued
    // If you need confirmation from two message because of a fork, you also need to pass the time the other one arrived
    function processMessage(
        address _to,
        uint256 _amount,
        address _bridge,
        uint256 _received_at_ts,
        uint256 _other_message_received_at_ts
    ) external {
        bytes32 messageID = keccak256(
            abi.encodePacked(_to, _amount, _bridge, _received_at_ts)
        );
        require(queuedMessages[messageID] > 0, "No message to retry");

        require(
            _handleMessage(
                _to,
                _amount,
                _bridge,
                _received_at_ts,
                _other_message_received_at_ts
            ),
            "Handling failed"
        );
        queuedMessages[messageID] = queuedMessages[messageID] - 1;
    }

    function _processPayment(
        address _to,
        uint256 _amount
    ) internal returns (bool) {
        return token.transfer(_to, _amount);
    }

    function _isMessageOldEnough(uint256 _ts) internal view returns (bool) {
        return (block.timestamp >= _ts + DELAY_SECS);
    }

    function _handleMessage(
        address _to,
        uint256 _amount,
        address _bridge,
        uint256,
        uint256 _other_message_received_at_ts
    ) internal returns (bool) {
        require(_bridge != address(0x0));

        address required_bridge1;
        address required_bridge2;
        (required_bridge1, required_bridge2) = forkmanager.requiredBridges();

        if (required_bridge1 == address(0)) {
            // Frozen or replaced
            // Need to either wait or call updateForkManager
            return false;
        } else if (required_bridge2 == address(0)) {
            // Normal status with one bridge
            require(
                _bridge == required_bridge1,
                "Requested bridge not allowed"
            );
            return _processPayment(_to, _amount);
        } else {
            // Forking state, we need a message from both bridges
            if (_other_message_received_at_ts == 0) {
                return false;
            }

            // Whichever bridge this message is coming from, see if we already got another message from the other one
            address otherBridge;
            bool found = false;
            if (msg.sender == required_bridge1) {
                otherBridge = required_bridge2;
                found = true;
            } else if (msg.sender == required_bridge2) {
                otherBridge = required_bridge1;
                found = true;
            }

            require(found, "Specified bridge not allowed");

            // If we've got the message from both, remove the queued one and go ahead
            bytes32 messageID = keccak256(
                abi.encodePacked(
                    _to,
                    _amount,
                    otherBridge,
                    _other_message_received_at_ts
                )
            );
            if (queuedMessages[messageID] == 0) {
                return false;
            }

            _processPayment(_to, _amount);
            queuedMessages[messageID] = queuedMessages[messageID] - 1;
            return true;
        }
    }

    function updateForkManager() external {
        ForkManager replaced = forkmanager.replacedByForkManager();
        require(
            address(replaced) != address(0x0),
            "ForkManager has not changed"
        );
        forkmanager = replaced;
    }
}
