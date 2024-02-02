// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

interface IMinimalAdjudicationFrameworkErrors {
    /// @dev Error thrown with illegal modification of arbitrators
    error NoArbitratorsToModify();
    /// @dev Error thrown when a proposition already exists
    error PropositionAlreadyExists();
    /// @dev Error thrown when a proposition is not found
    error PropositionNotFound();
    /// @dev Error thrown when a proposition is not found
    error ArbitratorNotInAllowList();
    /// @dev Error thrown when an arbitrator is already frozen
    error ArbitratorAlreadyFrozen();
    /// @dev Error thrown when received messages from realityEth is not yes
    error AnswerNotYes();
    /// @dev Error thrown when received messages from realityEth is yes, but expected to be no
    error PropositionNotFailed();
    /// @dev Error thrown when bond is too low to freeze an arbitrator
    error BondTooLowToFreeze();
    /// @dev Error thrown when proposition is not accepted
    error PropositionNotAccepted();
}
