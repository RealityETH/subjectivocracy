
import "@RealityETH/zkevm-contracts/contracts/PolygonZkEVMBridge.sol";

contract ForkableBridge is PolygonZkEVMBridge {

    // The forkmanager is the only one who can create children
    address public forkmanager;
    address public parentBridge;
    address[] public children = new address[](2);

    constructor(address _forkmanager, address _parentBridge) PolygonZkEVMBridge() {
        forkmanager = _forkmanager; 
        parentBridge = _parentBridge;
    }

    /**
     * @notice allows the forkmanager to create the new children
     */
    function createChildren() external {
        require(msg.sender == forkmanager, "Only forkmanager can create children");
        ForkableBridge forkableBridge = address(new ForkableBridge(forkmanager, address(this)));
        // forkableBridge.initialize(super.networkId, super.globalExitRootManger.getFirstChild(), 
        // super.polygonZKEVMaddress.getFirstChild(), super.gasTokenAddress.getFirstChild(),super.isDeployedOnl2);
        children[0] = address(forkableBridge);
        forkableBridge = new ForkableBridge(forkmanager, address(this));   
        children[1] = address(forkableBridge);
    }

    /**
     * @notice Anyone can use their tokens to split the bridged tokens into the two corresponding children tokens
     * @param token token that should be split
     * @param originNetwork origin network of the token to be split
     * @param amount amount of tokens to be split
     */
    function splitTokenIntoChildTokens(ERC20 token, uint256 originNetwork, uint256 amount) external {
        require(children[0] != address(0), "Children not created yet");
        require(children[1] != address(0), "Children not created yet");
        require(wrappedTokenToTokenInfo[token].originNetwork == super.networkId, "Token not forkable");
        require(TokenWrapped(token).burn(msg.sender, amount), "Burn failed");
        bytes memory metadata = abi.encodePacked(token.name(), token.symbol(), token.decimals());
        children[0].mintForkableToken(token, originNetwork, amount, metadata );
        children[1].mintForkableToken(token, originNetwork, amount,metadata);
    }

    function mintForkableToken(ERC20 token, uint256 originNetwork, uint256 amount, bytes metadata) external {
        require(msg.sender == parentBridge, "Only parent bridge can mint");
        require(wrappedTokenToTokenInfo[token].originNetwork != super.networkId, "Token is from this network");
        super.issueBridgedTokens(originNetwork, originTokenAddress,metadata, destinationAddress, amount );
    }

}