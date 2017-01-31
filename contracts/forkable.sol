pragma solidity ^0.4.7

// API defining the functions an exchange needs to be able to handle forks
contract ForkSavvy {
  event LogForkTokenSubscribe(address token, string subscribe_data);
  function creditForkedTokens(address user, uint256 balance) returns (bool) {}
}

// Example of a token that has forked from a previous token
contract ForkedToken {
  
  mapping (address=>mapping(address=>uint256)) managed_balances; 
  address public forkedFromToken;

  // This is defined by the ForkedToken.
  // It may also include other parameters like a merkel proof...
  // ...if the contract doesn't want to store data that may never be used
  function creditForkedTokensTo(address con, address user) returns (bool) {
    // We don't check that the contract actually has this balance
    if (ForkSavvy(con).creditForkedTokens(con, managed_balances[con][user])) {
      // We delete the balance, so the exchange doesn't have to worry about getting called twice
      managed_balances[con][user] = 0; 
      return true;
    }
    return false;
  }

}

// 
contract SomeExchange is ForkSavvy {

  // Event with a standard name to express the fact that we are interested in this data
  event LogForkTokenSubscribe(address token, string subscribe_data);

  mapping(address=>mapping(address=>uint256)) token_balances;

  function creditForkedTokens(address user, uint256 balance) returns (bool) {
    token_balances[msg.sender][user] += balance;
    return true;
  }

  // Example of initializing a token
  // The function doesn't need to be standard, as long as you call the event before the token forks
  // If you didn't call the event you could communicate to the forkers out-of-band
  // ...to let them know that you want your balances managed in their fork
  function initializeToken(address token) { 
    LogForkTokenSubscribe(token, "token_balances");
    // May also have its own setup logic for the forked token
  }

}
