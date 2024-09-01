// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

//price is per ton
contract FarmerContract {
    enum ContractStatus { Created, Fulfilled, Disputed, Completed }
    enum BuyerStatus{ Accepted,Disputed, Completed, Voided }
    struct Contract {
        address farmer;
        Buyer[] buyers;
        string[] conditions;
        uint quantity;
        uint price;
        ContractStatus status;
        bool negotiable;
        Bid[] bidList;
    }

    struct Bid {
        address buyer;
        uint price;
        uint quantity;
    }

    struct Buyer {
        address buyer;
        uint price;
        uint quantity;
        uint[] disputes;
        BuyerStatus status;
    }

    address public government;
    uint public contractCount = 0;
    mapping(uint => Contract) public contracts;

    event ContractCreated(uint contractId, address farmer, string[] conditions, uint quantity, uint price, bool negotiable);
    //buyer places a bid
    event BidPlaced(uint contractId, address buyer, uint quantity, uint price);
    //buyer accepts the contract that doesnt have a bidding system
    event ContractAccepted(uint contractId, address buyer, uint quantity, uint price);
    //when a contract with buyer is fulfilled and dispute was not valid
    event SubContractCompleted(uint contractId, address buyer);
    //when entire contract is completed
    event ContractCompleted(uint contractId);
    event ContractDisputed(uint contractId, address buyer, uint[] disputes);
    //when dispute verdict is given
    event ContractResolved(uint contractId, address buyer, bool success);
    //when quanitty filled
    event ContractFulfilled(uint contractId);
    //when dispute was valid
    event ContractVoided(uint contractId, address buyer);

    modifier onlyFarmer(uint contractId) {
        require(msg.sender == contracts[contractId].farmer, "Only farmer can call this function");
        _;
    }
    modifier onlyBuyer(uint contractId,address buyer) {
        uint i = findBuyerIndex(contractId, buyer);
        require(contracts[contractId].buyers[i].buyer == buyer && i < contracts[contractId].buyers.length, "Only buyer can call this function");
        _;
    }
    modifier onlyGovernment() {
        require(msg.sender == government, "Only government can call this function");
        _;
    }

    constructor() {
        government = msg.sender;
    }

    function createContract(string[] memory conditions, uint price,uint quantity, bool negotiable) external {
        Contract storage newContract = contracts[contractCount];
        newContract.farmer = msg.sender;
        newContract.conditions = new string[](0);
        for (uint i = 0; i < conditions.length; i++) {
            newContract.conditions.push(conditions[i]);
        }
        newContract.price = price;
        newContract.quantity = quantity;
        newContract.status = ContractStatus.Created;
        newContract.negotiable = negotiable;

        emit ContractCreated(contractCount, msg.sender, conditions, quantity, price, negotiable);
        contractCount++;
    }

    function bidPrice(uint contractId, uint price,uint quantity) external payable {
        Contract storage c = contracts[contractId];
        require(c.status == ContractStatus.Created, "The contract is not available for bidding");
        require(c.quantity >= quantity, "The quantity must be equal to or less than available quantity");
        require(msg.value == price*quantity, "Bid price must be sent with the bid");

        c.bidList.push(Bid(msg.sender, price, quantity));
        emit BidPlaced(contractId, msg.sender, quantity, price);
    }

    function acceptBid(uint contractId, address buyer) external onlyFarmer(contractId) {
        Contract storage c = contracts[contractId];
        uint uindex= findBidIndex(contractId,buyer);
        require(c.status == ContractStatus.Created, "Contract is not available for acceptance");
        require(uindex < c.bidList.length, "Invalid bid index");

        Bid storage acceptedBid = c.bidList[uindex];
        require(c.quantity >= acceptedBid.quantity, "The quantity must be equal to or less than required quantity");

        c.quantity -= acceptedBid.quantity;
    c.buyers.push(Buyer(buyer, acceptedBid.price, acceptedBid.quantity,new uint[](0),BuyerStatus.Accepted));
    delete c.bidList[uindex];
        //doubt: take money during bid or after farmer accepts.
    
        emit ContractAccepted(contractId, acceptedBid.buyer, acceptedBid.quantity, acceptedBid.price);

        if (c.quantity == 0) {
            c.status = ContractStatus.Fulfilled;
            freeBids(contractId);
            emit ContractFulfilled(contractId);
            
        }

    }
    
    function freeBids(uint contractId) internal { 
        Contract storage c = contracts[contractId];
        for(uint i=0;i<c.bidList.length;i++){
            if(c.bidList[i].buyer != address(0)){
            uint total=c.bidList[i].price * c.bidList[i].quantity ;
            (bool transferred,) = payable(c.bidList[i].buyer).call{value:total}("");
            require(transferred, "Payment failed.");
            }
        }
        delete c.bidList;
     }



    function acceptContract(uint contractId,uint quantity) external payable {
        Contract storage c = contracts[contractId];
        require(c.status == ContractStatus.Created, "Contract is not available for acceptance");
        require(c.negotiable==false,"Please place a bid. Contract cannot be accepted directly");
        require(c.quantity>=quantity,"The quantity must be equal to or less than required quantity");
        uint total=c.price * quantity ;
        require(msg.value == total , "Insufficient Bid Amount");
        c.buyers.push(Buyer(msg.sender, c.price,quantity,new uint[](0),BuyerStatus.Accepted));
        c.quantity-=quantity;  
        emit ContractAccepted(contractId, msg.sender,c.price,quantity);
        if (c.quantity== 0){ 
            c.status=ContractStatus.Fulfilled; 
            emit ContractFulfilled(contractId);
        }
    }

    function raiseDispute(uint contractId, uint[] memory disputes) external onlyBuyer(contractId,msg.sender)  {
        Contract storage c = contracts[contractId];
        require(c.status != ContractStatus.Completed , "Contract is already completed");
        
        uint uindex= findBuyerIndex(contractId ,msg.sender);
        require(uindex<c.buyers.length,"The buyer is not available");
        require(c.buyers[uindex].status == BuyerStatus.Accepted || c.buyers[uindex].status == BuyerStatus.Disputed,"Contract is already fulfilled or void");
        c.status = ContractStatus.Disputed;
        c.buyers[uindex].status = BuyerStatus.Disputed;
        delete c.buyers[uindex].disputes;
        for(uint i=0;i<disputes.length;i++){
            c.buyers[uindex].disputes.push(disputes[i]);
        }
        emit ContractDisputed(contractId,msg.sender,disputes);
    }

    function resolveDispute(uint contractId,address buyer, bool success) external onlyGovernment {
        Contract storage c = contracts[contractId];
        uint uindex= findBuyerIndex(contractId ,buyer);
        require(uindex<c.buyers.length,"The buyer is not available");
        require(c.status == ContractStatus.Disputed, "Contract is not in disputed state");
        require(c.buyers[uindex].status == BuyerStatus.Disputed,"The buyer is not in dispute");
        if (success) {
            c.buyers[uindex].status = BuyerStatus.Completed;
            
		    c.buyers[uindex].disputes = new uint[](0);
            uint total=c.buyers[uindex].price * c.buyers[uindex].quantity ;
            (bool transferred,) = payable(c.farmer).call{value:total}("");
            require(transferred, "Payment failed.");
            
            emit ContractResolved(contractId, buyer,true);
            emit SubContractCompleted(contractId,buyer);
            contractComplete(contractId);
        } else {
            c.buyers[uindex].status = BuyerStatus.Voided;  //ask if to delete or to keep
            c.quantity+= c.buyers[uindex].quantity;
            c.status=ContractStatus.Created;
            uint total=c.buyers[uindex].price * c.buyers[uindex].quantity ;
            (bool transferred,) = payable(c.buyers[uindex].buyer).call{value:total}("");
            require(transferred, "Payment failed.");
            emit ContractResolved(contractId,buyer, false);
            emit ContractVoided(contractId,buyer);
        }
        
        
    }
    function contractComplete(uint contractId) internal{
        bool allCompleted=true;
        Contract storage c = contracts[contractId];
        for(uint i=0 ;i<c.buyers.length ;i++){
            if(!(c.buyers[i].status== BuyerStatus.Completed || c.buyers[i].status== BuyerStatus.Voided )){
                allCompleted=false;
             }
         }
         if(allCompleted && c.quantity==0){
            c.status=ContractStatus.Completed;
            emit ContractCompleted(contractId);
         }
    }

    function confirmDelivery(uint contractId) external onlyBuyer(contractId,msg.sender) {
        Contract storage c = contracts[contractId];
        uint uindex= findBuyerIndex(contractId ,msg.sender);
        require(uindex<c.buyers.length,"The buyer is not available");

        require(c.buyers[uindex].status == BuyerStatus.Accepted, "Farmer contract is not in accepted state");
        c.buyers[uindex].status= BuyerStatus.Completed;
        
        uint total=c.buyers[uindex].price * c.buyers[uindex].quantity ;
        (bool transferred,) = payable(c.farmer).call{value:total}("");
            require(transferred, "Payment failed.");

        emit SubContractCompleted(contractId,msg.sender);
        contractComplete(contractId);
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

    function seeDispute(uint contractId, address buyer) external view returns (string[] memory) {
        Contract storage c = contracts[contractId];
        uint uindex = findBuyerIndex(contractId, buyer);
        require(uindex <c.buyers.length, "The buyer is not available");
        
        uint[] storage disputeIndices = c.buyers[uindex].disputes;
        string[] memory disputeStrings = new string[](disputeIndices.length);
        
        for (uint i = 0; i < disputeIndices.length; i++) {
            disputeStrings[i] = c.conditions[disputeIndices[i]];
        }
        
        return disputeStrings;
    }

    function findBuyerIndex(uint contractId, address buyer) internal view returns (uint) {
        Contract storage c = contracts[contractId];
        uint length=c.buyers.length;
        for (uint i = 0; i < length; i++) {
            if (c.buyers[i].buyer == buyer) {
                return i;
            }
        }
        return length;
    }
    function findBidIndex(uint contractId, address buyer) internal view returns (uint) {
        Contract storage c = contracts[contractId];
        uint length=c.bidList.length;
        for (uint i = 0; i < length; i++) {
            if (c.bidList[i].buyer == buyer) {
                return i;
            }
        }
        return length;
    }

    // Other functions like raiseDispute, resolveDispute, confirmDelivery, etc.
}