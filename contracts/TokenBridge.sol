pragma solidity ^0.4.25;

import './IERC20.sol';
import './ForkManager.sol';

contract TokenBridge {

    IERC20 token;
    IERC20 l2contract;
    ForkManager forkmanager;
    IAMB bridge;
    bytes32 homeChainId;
    address homeProxy;

     
    mapping(bytes32 => uint256) queuedMessages;

    constructor(IERC20 _token, bytes32 _homeChainId, address _homeProxy) 
    public {
        token = _token;
        homeChainId = _homeChainId;
        homeProxy = _homeProxy;
    }

    // You can send via whatever bridges you like, if they're shady it's your problem
    function sendToL2(uint256 _amount, address[] _bridges) 
    external {
        require(token.transferFrom(msg.sender, this, _amount), "Transfer failed");
        for(uint256 i=0; i<_bridges.length; i++) {
            bytes memory data = abi.encodeWithSelector(IERC20(homeProxy).mint.selector, msg.sender, _amount);
            IAMB(_bridges[i]).requireToPassMessage(l2contract, data, 0);
        }
    }

    // Handle a message from L2
    // If the message looks OK but the bridge is wrong, or we also need the same message from another bridge, queue it to retry later
    function receiveFromL2(address _to, uint256 _amount) 
    external {

        // We never want a message if the bridge says it comes from something other than the home proxy 
        require(IAMB(msg.sender).messageSender() != homeProxy, "Wrong home proxy") ;

        if (!_handleMessage(_to, _amount, msg.sender)) {
            // add to queue
            bytes32 messageID = keccak256(abi.encodePacked(_to, _amount, msg.sender)); 
            queuedMessages[messageID] = queuedMessages[messageID] + 1;
        }

    }

    // Retry a message that was previously queued because the bridge was wrong, or we needed another bridge too
    function retryMessage(address _to, uint256 _amount, address _bridge)
    external {
        bytes32 messageID = keccak256(abi.encodePacked(_to, _amount, _bridge)); 
        require(queuedMessages[messageID] > 0, "No message to retry");

        if (_handleMessage(_to, _amount, _bridge)) {
            // Remove from the queue
            queuedMessages[messageID] = queuedMessages[messageID] - 1;
        }

    }

    function _processPayment(address _to, uint256 _amount) 
    internal returns (bool) {
        return token.transfer(_to, _amount);
    }

    function _handleMessage(address _to, uint256 _amount, address _bridge) 
    internal returns (bool) {

        require(_bridge != address(0x0));

        address[] memory required_bridges = forkmanager.requiredBridges();

        if (required_bridges.length < 1) {

            // Frozen or replaced
            // Need to either wait or call updateForkManager
            return false;

        } else if (required_bridges.length == 1) {

            // Normal status with one bridge
            if (_bridge == required_bridges[0]) {
                return _processPayment(_to, _amount);
            } else {
                return false;
            }

        } else {

            // Forking state, we need a message from both bridges

            // Whichever bridge this message is coming from, see if we already got another message from the other one
            address otherBridge;
            bool found = false;
            if (msg.sender == required_bridges[0]) {
                otherBridge = required_bridges[1];
                found = true;
            } else if (msg.sender == required_bridges[1]) {
                otherBridge = required_bridges[0];
                found = true;
            }

            if (!found) {
                return false;
            }

            // If we've got the message from both, remove the queued one and go ahead
            bytes32 messageID = keccak256(abi.encodePacked(_to, _amount, otherBridge)); 
            if (queuedMessages[messageID] == 0) {
                return false;
            }

            _processPayment(_to, _amount);
            queuedMessages[messageID] = queuedMessages[messageID] - 1;
            return true;
        }

    }

    function updateForkManager() 
    external {
        ForkManager replaced = forkmanager.replacedByForkManager();
        require(address(replaced) != address(0x0), "ForkManager has not changed");
        forkmanager = replaced;
    }
    
}
