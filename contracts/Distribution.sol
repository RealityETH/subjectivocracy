pragma solidity ^0.4.15;

import "./RealityToken.sol";

contract Distribution{
   mapping(address => uint256) balances;
   address public owner;
   bool isFinished;

   event Withdraw(bytes32 hashid, address user);

   modifier isOwner(){
    require(msg.sender == owner);
    _;
   }


   modifier notYetFinished(){
    require(!isFinished);
    _;
   }

   //Constructor sets the owner of the Distribution
   function Distribution()
   public {
     owner = msg.sender;
   }

   //@param users list of users that should be rewarded
   //@param fundAmount list of amounts the users should be funded with
   function injectReward(address[] user, uint[] fundAmount_)
   isOwner()
   notYetFinished()
   public
   {
      for(uint i=0; i<user.length;i++)
          balances[user[i]] = fundAmount_[i];
   }

   function finalize()
   isOwner()
   public{
     isFinished = true;
   }

   // param hashid_ hashid_ should be the hash of the branch 
   function withdrawReward(address realityToken, bytes32 hashid_) public {
     RealityToken(realityToken).transfer(msg.sender, balances[msg.sender], hashid_);
     balances[msg.sender] = 0;
     emit Withdraw(hashid_, msg.sender);
   }
}