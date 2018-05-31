pragma solidity ^0.4.15;

contract ArbitratorData{
   mapping(bytes32 => bytes32) answersBytes;
   mapping(bytes32 => uint256) answerTime;
   mapping(bytes32 => uint8) answerConfidence; // 0 is high confidence - 7 is low confidence

   address public owner;
   uint public realityArbitrationCost;  
   
   event Answer(bytes32 hashid, bytes32 answer);
   
   modifier isOwner(){
    require(msg.sender == owner);
    _;
   }

   //Constructor sets the owner of the DataContract
   //@param additionalSupportedDapps  adds a additional Dapps to the list of supported Dapps
   //@param noLongerSupportedDapps list of dapps, which should no longer supported
   function ArbitratorData()
   public {
     owner = msg.sender;
   }


   // allows to set a new setArbitrationCost
   // @param cost_ the cost for all future arbitration costs needed to pay before arbitration.
   function setArbitrationCost(uint cost_)
    isOwner()
   public 
   {
      realityArbitrationCost = cost_;
   }


   //@dev all answeres needs to be submitted here. Timestamp of answer is stored. 
   function addAnswer(bytes32[] hashid_, bytes32[] answer_, uint8[] answerConfidence_)
      isOwner()
      public
   {
      for(uint i=0;i < hashid_.length; i++){
        answersBytes[hashid_[i]] = answer_[i];
        answerTime[hashid_[i]] = now;
        answerConfidence[hashid_[i]] = answerConfidence_[i];  
        emit Answer(hashid_[i], answer_[i]);
      }
    }

   //@dev gives the answer of the arbitrator 
   //@param hashid_ is the hash id of the answer
   function getAnswer(bytes32 hashid_) constant public returns (bytes32){
     require(answerTime[hashid_] > 0);
     return answersBytes[hashid_];
   }

   function isAnswerSet(bytes32 hashid_) constant public returns (bool){
     if(answerTime[hashid_] > 0)
        return true;
     else 
        return false;
   }
   //@dev gives the answer of the arbitrator, if the arbitrator submitted it before a certain time. 
   //@param hashid_ is the hash id of the answer
   //@param timethreshold is the threshold until when answers were trustworthy of the arbitrator.
   function getAnswerBefore(bytes32 hashid_, uint timethreshold) constant public returns (bytes32){
     require(answerTime[hashid_] > 0);
     require(timethreshold >= answerTime[hashid_]);
     return answersBytes[hashid_];
   }

   function isAnswerSetBefore(bytes32 hashid_,  uint timethreshold) constant public returns (bool){
     if(answerTime[hashid_] <= timethreshold)
        return true;
     else 
        return false;
   }
}