pragma solidity ^0.4.1;

contract RealityTokenFactory {

    uint256 public genesis_window_timestamp;
    RealityToken public genesis_token;

    function RealityTokenFactory() {
        address NULL_ADDRESS;
        genesis_window_timestamp = now - (now % 86400);
        genesis_token = new RealityToken(0, NULL_ADDRESS, genesis_window_timestamp, msg.sender);
    }

    function createFork(address _parent, uint256 _window) {
        RealityToken rt = new RealityToken(_window, _parent, genesis_window_timestamp, msg.sender);
    }

}
