// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

/* solhint-disable quotes */
/* solhint-disable not-rely-on-time */

import {BalanceHolder} from "./../../lib/reality-eth/BalanceHolder.sol";
import {IRealityETH} from "./../../lib/reality-eth/interfaces/IRealityETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MinimalAdjudicationFramework} from "./../MinimalAdjudicationFramework.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/*
This contract is an example implementation of price feeds using the backstop's arbitration framework.
The final contract will depend on customer requirements.
*/

contract AdjudicationFrameworkFeeds is MinimalAdjudicationFramework {
    using EnumerableSet for EnumerableSet.AddressSet;

    // each arbitrator can provide 5 inputs, before old inputs will be overwritten.
    uint256 public constant INPUT_SIZE = 5;

    // Input struct from oracle price providers
    struct Input {
        uint256 price;
        uint256 timestamp;
    }

    // token => Arbitrator => inputNr % INPUT_SIZE => Input
    mapping(address => mapping(address => mapping(uint256 => Input)))
        public arbitratorInputs;

    /// @param _realityETH The reality.eth instance we adjudicate for
    /// @param _forkArbitrator The arbitrator contract that escalates to an L1 fork, used for our governance
    /// @param _initialArbitrators Arbitrator contracts we initially support
    constructor(
        address _realityETH,
        address _forkArbitrator,
        address[] memory _initialArbitrators
    )
        MinimalAdjudicationFramework(
            _realityETH,
            _forkArbitrator,
            _initialArbitrators
        )
    {}

    /**
     @dev Allows an arbitrator to provide price feeds
     @param tokens The tokens for which the arbitrator provides feeds
        @param prices The prices for the tokens
     */
    function provideInput(
        address[] calldata tokens,
        uint256[] calldata prices
    ) external onlyArbitrator {
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 lastEntry = INPUT_SIZE - 1;
            for (uint j = 0; j < INPUT_SIZE; j++) {
                if (
                    arbitratorInputs[tokens[i]][msg.sender][j].timestamp >
                    arbitratorInputs[tokens[i]][msg.sender][lastEntry].timestamp
                ) {
                    lastEntry = j;
                } else {
                    // we can break early, since entries are ordered by timestamp % INPUT_SIZE
                    break;
                }
            }
            arbitratorInputs[tokens[i]][msg.sender][
                (lastEntry + 1) % INPUT_SIZE
            ] = Input(prices[i], block.timestamp);
        }
    }

    /** 
    @dev Provides the latest price
    @return the latest price
     */
    function getPrice(address token) external view returns (uint256) {
        return getPriceConsideringDelay(token, 0);
    }

    /** 
    @dev Provides the latest price considering a delay, that allows other to escalate and freeze wrong oracle inputs
     */
    function getPriceConsideringDelay(
        address token,
        uint256 delay
    ) public view returns (uint256) {
        uint256 arbitratorCount = arbitrators.length();
        uint256[] memory prices = new uint256[](arbitratorCount);
        for (uint i = 0; i < arbitratorCount; i++) {
            address arbitrator = arbitrators.at(i);
            if (countArbitratorFreezePropositions[arbitrator] > 0) {
                continue;
            }
            uint256 lastEntry = 0;
            for (uint j = 0; j < INPUT_SIZE; j++) {
                if (
                    arbitratorInputs[token][arbitrator][j].timestamp <
                    arbitratorInputs[token][arbitrator][lastEntry].timestamp &&
                    arbitratorInputs[token][arbitrator][j].timestamp >
                    block.timestamp - delay
                ) {
                    lastEntry = j;
                } else {
                    // we can break early, since entries are ordered by timestamp % INPUT_SIZE
                    break;
                }
            }
            prices[i] = arbitratorInputs[token][arbitrator][lastEntry].price;
        }

        //Todo: can we also return the median?
        return calculateAverage(prices);
    }

    /**
    @dev Calculates the average of a list of prices
    @param prices The prices used to calculate the average
     */
    function calculateAverage(
        uint256[] memory prices
    ) public pure returns (uint256) {
        uint256 sum = 0;
        uint256 count = 0;
        for (uint i = 0; i < prices.length; i++) {
            if (prices[i] != 0) {
                sum += prices[i];
                count++;
            }
        }
        if (count == 0) {
            return 0;
        }
        return sum / count;
    }
}
