pragma solidity ^0.8.17;

import "./IForkableStructure.sol";

interface IForkingManager is IForkableStructure {
    function initialize(
        address _zkEVM,
        address _bridge,
        address _forkonomicToken,
        address _parentContract,
        uint256 _arbitrationFee
    ) external;
}
