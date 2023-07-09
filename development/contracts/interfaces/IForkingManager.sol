pragma solidity ^0.8.17;

import "./IForkableStructure.sol";

interface IForkingManager is IForkableStructure {
    function initialize(
        address _zkEVM,
        address _bridge,
        address _forkonomicToken,
        address _parentContract,
        address _globalExitRoot,
        uint256 _arbitrationFee
    ) external;
}
