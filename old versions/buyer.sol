// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

//all prices are per ton
contract BuyerContract {
    enum ContractStatus { Created,Fulfilled, Disputed, Completed }
    enum FarmerStatus{ Accepted, Disputed, Completed, Voided  }
    
    struct Contract {
        address buyer;
        Farmer[] farmers;
        address[] farmerAddresses;
        string[] conditions;
        uint quantity;
        //price per ton
        uint price;
        ContractStatus status;
        bool negotiable;
        Bid[] bidList;
    }
    struct Bid{
        address farmer;
        uint price;
        uint quantity;
    }
    struct Farmer {
        address farmer;
        uint price;
        uint quantity;
        uint[] disputes;
        FarmerStatus status;
    }


    address public government;
    uint public contractCount=0;
    mapping(uint => Contract) public contracts;

    event ContractCreated(uint contractId, address buyer, string[] conditions, uint quantity,uint price ,bool negotiable);
    event ContractAccepted(uint contractId, address farmer,uint quantity,uint price);
    event ContractPriceProposal(uint contractId,address farmer,uint quantity,uint price);
    event ContractDisputed(uint contractId,address farmer,uint[] disputes);
    event ContractResolved(uint contractId, address farmer,bool success);
    event ContractCompleted(uint contractId,address farmer);
    event ContractFulfilled(uint contractId);
    event ContractVoided(uint contractId,address farmer);

    modifier onlyBuyer(uint contractId) {
        require(msg.sender == contracts[contractId].buyer, "Only buyer can call this function");
        _;
    }

    // modifier onlyFarmer(uint contractId) {
    //     require(msg.sender == contracts[contractId]., "Only farmer can call this function");
    //     _;
    // }

    modifier onlyGovernment() {
        require(msg.sender == government, "Only government can call this function");
        _;
    }

    constructor() {
        government = msg.sender;
    }
    //contract created by buyer
    function createContract(string[] memory conditions, uint quantity,uint price,bool negotiable) external {
        Contract storage newContract =contracts[contractCount];
        newContract.buyer= msg.sender;
        delete newContract.conditions;
        for(uint i=0;i<conditions.length;i++){
            newContract.conditions.push(conditions[i]);
        }
        newContract.price= price;
        newContract.quantity=quantity;
        newContract.status= ContractStatus.Created;
        newContract.negotiable= negotiable;

        emit ContractCreated(contractCount, msg.sender, conditions, quantity,price,negotiable);
        contractCount++;
    }
    function displayBids(uint contractId) external view returns (Bid[] memory) {
    Contract storage c = contracts[contractId];
    return c.bidList;
}
    function displayContracts() external view returns (Contract[] memory) {
    Contract[] memory contractList = new Contract[](contractCount);
    for (uint i = 0; i < contractCount; i++) {
        contractList[i] = contracts[i];
    }
    return contractList;
}
function seeDispute(uint contractId, address farmer) external view returns (string[] memory) {
    Contract storage c = contracts[contractId];
    uint uindex = findFarmerIndex(contractId, farmer);
    require(uindex <c.farmers.length, "The farmer is not available");

    
    uint[] storage disputeIndices = c.farmers[uindex].disputes;
    string[] memory disputeStrings = new string[](disputeIndices.length);
    
    for (uint i = 0; i < disputeIndices.length; i++) {
        disputeStrings[i] = c.conditions[disputeIndices[i]];
    }
    
    return disputeStrings;
}
    //farmer dispute
    function findBidIndex(uint contractId,address farmer) internal view returns(uint){
        Contract storage c = contracts[contractId];
        uint length=c.bidList.length;
        for(uint i=0 ;i<length ;i++){
            if(c.bidList[i].farmer== farmer){
                return i; 
            }
        }
        return length ;
    }
    function findFarmerIndex(uint contractId ,address farmer) internal view returns(uint){
        Contract storage c = contracts[contractId];
        uint length=c.farmers.length;
        for(uint i=0 ;i< length;i++){
            if(c.farmers[i].farmer== farmer){
                return i; 
             }
         }
        return length ;
     }
    
    function acceptBid(uint contractId,address farmer) external payable onlyBuyer(contractId)  {
        Contract storage c = contracts[contractId];
        uint uindex= findBidIndex(contractId,farmer);
        require(uindex<c.bidList.length,"The bid is not available");
        uint price=c.bidList[uindex].price;
        uint quantity=c.bidList[uindex].quantity;

        
        require(price*quantity==msg.value,"The price is not same as negotiation");
        require(c.bidList[uindex].farmer==farmer,"Not the same farmer");
        require(c.negotiable==true && c.status==ContractStatus.Created, "Contract is not available for negotiation");
        require( c.quantity- quantity>=0,"Quantity greater than required");
        
        c.farmers.push(Farmer(msg.sender ,c.price*quantity,quantity,new uint[](0), FarmerStatus.Accepted));
        delete c.bidList[uindex]; 
        
        c.quantity-=quantity;
        emit ContractAccepted(contractId, farmer,price,quantity);
        if (c.quantity== 0){ 
            c.status=ContractStatus.Fulfilled; 
            delete c.bidList;
            emit ContractFulfilled(contractId);
        }
        //add option for adding to current contract
       
        
    }

    function bidPrice(uint contractId,uint quantity,uint price) external  {
        Contract storage c= contracts[contractId];
        require(c.negotiable==true && c.status==ContractStatus.Created,"The contract is not available for negotiation");
        require(c.quantity>=quantity,"The quantity must be equal to or less than required quantity");
        c.bidList.push(Bid(msg.sender,price,quantity));
        emit ContractPriceProposal(contractId,msg.sender,quantity,price);
    }
    function acceptContract(uint contractId,uint quantity) external {
        Contract storage c = contracts[contractId];
        require(c.status == ContractStatus.Created, "Contract is not available for acceptance");
        require(c.negotiable==false,"Please place a bid. Contract cannot be accepted directly");
        require(c.quantity>=quantity,"The quantity must be equal to or less than required quantity");
        c.farmers.push(Farmer(msg.sender ,c.price*quantity,quantity,new uint[](0), FarmerStatus.Accepted));
        c.quantity-=quantity;  
        emit ContractAccepted(contractId, msg.sender,c.price,quantity);
        if (c.quantity== 0){ 
            c.status=ContractStatus.Fulfilled; 
            emit ContractFulfilled(contractId);
        }
        

    }

    function raiseDispute(uint contractId,address farmer, uint[] memory disputes) external onlyBuyer(contractId)  {
        Contract storage c = contracts[contractId];
        require(c.status != ContractStatus.Completed, "Contract is already completed");
        
        uint uindex= findFarmerIndex(contractId ,farmer);
        require(uindex<c.farmers.length,"The farmer is not available");
        //allows overwriiting disputes
        require(c.farmers[uindex].status == FarmerStatus.Accepted || c.farmers[uindex].status == FarmerStatus.Disputed ,"The farmer is not in accepted state");
        c.status = ContractStatus.Disputed;
        c.farmers[uindex].status = FarmerStatus.Disputed;
        delete c.farmers[uindex].disputes;
        for(uint i=0;i<disputes.length;i++){
            c.farmers[uindex].disputes.push(disputes[i]);
        }
        emit ContractDisputed(contractId,farmer,disputes);
    }

    function resolveDispute(uint contractId,address farmer, bool success) external onlyGovernment {
        Contract storage c = contracts[contractId];
        uint uindex= findFarmerIndex(contractId ,farmer);
        require(uindex<c.farmers.length,"The farmer is not available");

        require(c.status == ContractStatus.Disputed, "Contract is not in disputed state");
        require(c.farmers[uindex].status == FarmerStatus.Disputed,"The farmer is not in dispute");
        if (success) {
            c.farmers[uindex].status = FarmerStatus.Completed;
            contractComplete(contractId);
		    c.farmers[uindex].disputes = new uint[](0);
            uint total=c.farmers[uindex].price * c.farmers[uindex].quantity ;
            (bool transferred,) = payable(farmer).call{value:total}("");
            require(transferred, "Payment failed.");
            
            emit ContractResolved(contractId, farmer,true);
            emit ContractCompleted(contractId,farmer);
        } else {
            c.farmers[uindex].status = FarmerStatus.Voided;  //ask if to delete or to keep
            c.quantity+= c.farmers[uindex].quantity;
            c.status=ContractStatus.Created;
            uint total=c.farmers[uindex].price * c.farmers[uindex].quantity ;
            (bool transferred,) = payable(c.buyer).call{value:total}("");
            require(transferred, "Payment failed.");
            emit ContractResolved(contractId,farmer, false);
            emit ContractVoided(contractId,farmer);
        }
        
        
    }
    function contractComplete(uint contractId) internal{
        bool allCompleted=true;
        Contract storage c = contracts[contractId];
        for(uint i=0 ;i<c.farmers.length ;i++){
            if(!(c.farmers[i].status== FarmerStatus.Completed || c.farmers[i].status== FarmerStatus.Voided) ){
                allCompleted=false;
             }
         }
         if(allCompleted && c.quantity==0){
            c.status=ContractStatus.Completed;
         }
    }

    function confirmDelivery(uint contractId,address farmer) external onlyBuyer(contractId) {
        Contract storage c = contracts[contractId];
        uint uindex= findFarmerIndex(contractId ,farmer);
        require(uindex<c.farmers.length,"The farmer is not available");

        require(c.farmers[uindex].status == FarmerStatus.Accepted, "Farmer contract is not in accepted state");
        c.farmers[uindex].status= FarmerStatus.Completed;
        contractComplete(contractId);
        uint total=c.farmers[uindex].price * c.farmers[uindex].quantity ;
        (bool transferred,) = payable(farmer).call{value:total}("");
        require(transferred, "Payment failed.");

        emit ContractCompleted(contractId,farmer);
    }

    
}

