pragma solidity ^0.4.15;

contract ArbitratorList{

   address[] public arbitrators;

   //Constructor sets the arbitrators of the contract
   function ArbitratorList(address[] arbitrators_)
   public {
     arbitrators = arbitrators_;
   }
}