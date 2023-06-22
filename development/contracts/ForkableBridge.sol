pragma solidity ^0.8.17;

import "@RealityETH/zkevm-contracts/contracts/PolygonZkEVMBridge.sol";
import "@RealityETH/zkevm-contracts/contracts/lib/TokenWrapped.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "./interfaces/IForkableBridge.sol";

contract ForkableBridge is PolygonZkEVMBridge, IForkableBridge {
    address public forkmanager;
    address public parentBridge;
    address[] public children = new address[](2);

    modifier onlyParent() {
        require(msg.sender == parentBridge);
        _;
    }

    modifier onlyForkManger() {
        require(msg.sender == forkmanager);
        _;
    }

    function initialize(
        address _forkmanager,
        address _parentBridge
    ) external initializer {
        forkmanager = _forkmanager;
        parentBridge = _parentBridge;
        // todo: overwrite the initialization once interfaces are correct.
        // PolygonZkEVMBridge.initialize(_forkmanager, _parentBridge);
    }

    /**
     * @notice Allows the forkmanager to create the new children
     */
    function createChildren() external onlyForkManger {
        address forkableBridge = ClonesUpgradeable.clone(address(this));
        // Todo: forkableBridge.initialize(super.networkId, super.globalExitRootManger.getFirstChild(),
        // super.polygonZKEVMaddress.getFirstChild(), super.gasTokenAddress.getFirstChild(),super.isDeployedOnl2);
        children[0] = forkableBridge;
        forkableBridge = ClonesUpgradeable.clone(address(this));
        // Todo: forkableBridge.initialize(super.networkId, super.globalExitRootManger.getFirstChild(),
        // super.polygonZKEVMaddress.getFirstChild(), super.gasTokenAddress.getFirstChild(),super.isDeployedOnl2);
        children[1] = forkableBridge;
    }

    /**
     * @notice Anyone can use their tokens to split the bridged tokens into the two corresponding children tokens
     * @param token token that should be split
     * @param originNetwork origin network of the token to be split
     * @param amount amount of tokens to be split
     */
    function splitTokenIntoChildTokens(
        ERC20 token,
        uint32 originNetwork,
        uint256 amount
    ) external {
        require(children[0] != address(0), "Children not created yet");
        require(children[1] != address(0), "Children not created yet");
        require(
            wrappedTokenToTokenInfo[address(token)].originNetwork != 0,
            "Token not forkable"
        );
        TokenWrapped(address(token)).burn(msg.sender, amount);
        bytes memory metadata = abi.encodePacked(
            token.name(),
            token.symbol(),
            token.decimals()
        );
        ForkableBridge(children[0]).mintForkableToken(
            token,
            originNetwork,
            amount,
            metadata,
            msg.sender
        );
        ForkableBridge(children[1]).mintForkableToken(
            token,
            originNetwork,
            amount,
            metadata,
            msg.sender
        );
    }

    function mintForkableToken(
        ERC20 token,
        uint32 originNetwork,
        uint256 amount,
        bytes calldata metadata,
        address destinationAddress
    ) external onlyParent {
        require(
            wrappedTokenToTokenInfo[address(token)].originNetwork != networkID,
            "Token is from this network"
        );
        issueBridgedTokens(
            originNetwork,
            address(token),
            metadata,
            destinationAddress,
            amount
        );
    }

    function getChild(uint256 index) external view returns (address) {
        return children[index];
    }

    // This function will be present in the inherited contract, once the other PR is merged
    function issueBridgedTokens(
        uint32 originNetwork,
        address originTokenAddress,
        bytes memory metadata,
        address destinationAddress,
        uint256 amount
    ) internal {
        // Create a wrapper for the token if not exist yet
        bytes32 tokenInfoHash = keccak256(
            abi.encodePacked(originNetwork, originTokenAddress)
        );
        address wrappedToken = tokenInfoToWrappedToken[tokenInfoHash];

        if (wrappedToken == address(0)) {
            // Get ERC20 metadata
            (string memory name, string memory symbol, uint8 decimals) = abi
                .decode(metadata, (string, string, uint8));

            // Create a new wrapped erc20 using create2
            TokenWrapped newWrappedToken = (new TokenWrapped){
                salt: tokenInfoHash
            }(name, symbol, decimals);

            // Mint tokens for the destination address
            newWrappedToken.mint(destinationAddress, amount);

            // Create mappings
            tokenInfoToWrappedToken[tokenInfoHash] = address(newWrappedToken);

            wrappedTokenToTokenInfo[
                address(newWrappedToken)
            ] = TokenInformation(originNetwork, originTokenAddress);

            emit NewWrappedToken(
                originNetwork,
                originTokenAddress,
                address(newWrappedToken),
                metadata
            );
        } else {
            // Use the existing wrapped erc20
            TokenWrapped(wrappedToken).mint(destinationAddress, amount);
        }
    }
}
