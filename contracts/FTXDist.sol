pragma solidity ^0.4.18;

import './math/SafeMath.sol';
import "./FTXToken.sol";
import "./ownership/Ownable.sol";
import "./HasNoTokens.sol";
import "./FTXPrivatePresale.sol";
import "./FTXPublicPresale.sol";
import "./FTXSale.sol";

contract FTXDist is Ownable, HasNoTokens {
    using SafeMath for uint256;

    string public constant NAME = "FintruX token distribution";
    string public constant VERSION = "0.7";

    FTXToken            token;
    FTXPrivatePresale   privatePresale;
    FTXPublicPresale    publicPresale;
    FTXSale             crowdSale;

    uint256 public purchaserCount = 0;                                              // total number of purchasers purchased FTX
    uint256 public purchaserDistCount = 0;                                          // total number of purchasers received purchased FTX + bonus
    uint256 public purchaserLeftoverDistCount = 0;                                  // total number of purchasers received(may be zero) leftover portion
    uint256 public tokensSold = 0;                                                  
    uint256 public minFtxPurchase = 0;
    uint256 public tokenHardCap = 0;
    /** this becomes true when crowdsale has distributed purchased tokens with bonus for each purchaser address */
    mapping (address => bool) public tokenDistributed;

    /** the amount of leftover tokens this crowdsale has distributed for each purchaser address */
    mapping (address => uint256) public leftoverAmountOf;

    /** this becomes true when crowdsale has distributed leftover tokens for each purchaser address */
    mapping (address => bool) public leftoverDistributed;

    event TokenDistributed(address indexed purchaser, uint256 tokenAmt);            // event logging for each individual distributed token + bonus
    event LeftoverTokenDistributed(address indexed purchaser, uint256 tokenAmt);    // event logging for each individual distributed leftover

    /*
        Constructor to initialize everything.
    */
    function FTXDist (address _privatePresale, address _publicPresale, address _crowdsale, address _token, address _owner) public {
        if (_owner == address(0)) {
            _owner = msg.sender;
        }
        require(_privatePresale != address(0));
        require(_publicPresale != address(0));
        require(_crowdsale != address(0));
        require(_owner != address(0));                
        token = FTXToken(_token);
        owner = _owner;                                                             // default owner
 
        privatePresale = FTXPrivatePresale(_privatePresale);
        publicPresale = FTXPublicPresale(_publicPresale);
        crowdSale = FTXSale(_crowdsale);
        purchaserCount = crowdSale.purchaserCount();                                // initialize to all purchaser count
        tokensSold = crowdSale.tokensSold();                                        // initialize token sold from crowd sale
        minFtxPurchase = crowdSale.MIN_FTX_PURCHASE();
        tokenHardCap = crowdSale.TOKEN_HARD_CAP();
    }
    
    function setTokenContract(address _token) external onlyOwner {
        require(token != address(0));
        token = FTXToken(_token);
        
    }

    /*
        Distribute tokens purchased with bonus.
    */
    function distributeTokensFor(address purchaser) external onlyOwner {
        require(token != address(0));
        require(crowdSale.isFinalized());
        require(crowdSale.isMinimumGoalReached());
        require(!tokenDistributed[purchaser]);
        tokenDistributed[purchaser] = true;                           // token + bonus distributed
        uint256 tokenPurchased = crowdSale.tokenAmountOf(purchaser) + privatePresale.tokenAmountOf(purchaser) + publicPresale.tokenAmountOf(purchaser);
        purchaserDistCount++;                                         // one more purchaser received token + bonus
        // transfer the purchased tokens + bonus
        token.transfer(purchaser, tokenPurchased);
        // signal the event for communication
        TokenDistributed(purchaser, tokenPurchased);

        // clean up the account if all purchasers have received tokens + bonus and there is no unsold tokens
        if (purchaserDistCount >= purchaserCount && !hasLeftoverTokens()) {
            uint256 remaining = token.balanceOf(address(this));
            if (remaining >= token.token4Gas()) {
                token.transfer(owner, token.balanceOf(address(this)));  // Balance everything out
            }
            else {
                // odd case that the token transfer limit is larger than tiny left over, what to do ?
            }
        }
    }

    function calcLeftoverTokens(address purchaser) public view returns (uint256) {
        uint256 allocatedLeftover = 0;
        uint256 remaining = token.balanceOf(address(this));
        uint256 tokenPurchased = crowdSale.tokenAmountOf(purchaser) + privatePresale.tokenAmountOf(purchaser) + publicPresale.tokenAmountOf(purchaser);
        // Send leftover tokens out proporationally if not fully sold.
        if (hasLeftoverTokens()) {
            allocatedLeftover = SafeMath.cei((tokenPurchased * (tokenHardCap - tokensSold)) / tokensSold, 10**18);
            /* The following would only function properly in the actual distribution, not in estimation */
            if (remaining < allocatedLeftover) {                           // In case not enough remaining
                allocatedLeftover = remaining;
            }
            uint256 minTokenToTransfer = token.token4Gas();                
            if (allocatedLeftover < minTokenToTransfer) {                  // too small, given them zero
                allocatedLeftover = 0;
            }                    
        }

        return allocatedLeftover;
    }
    /*
        Distribute leftover tokens one time.
    */
    function distributeLeftover(address purchaser) external onlyOwner {
        require(token != address(0));
        require(crowdSale.isFinalized());
        require(crowdSale.isMinimumGoalReached());
        require(purchaserDistCount >= purchaserCount);                    // only when all purchased token + bonus is distributed
        require(!leftoverDistributed[purchaser]);                         // distribute once only
        require(token.balanceOf(address(this)) > 0);                      // must not be empty

        uint256 allocatedLeftover = 0;
        uint256 remaining = token.balanceOf(address(this));
        //uint256 tokenPurchased = crowdSale.tokenAmountOf(purchaser) + privatePresale.tokenAmountOf(purchaser) + publicPresale.tokenAmountOf(purchaser);
        // Send leftover tokens out proporationally if not fully sold.
        allocatedLeftover = calcLeftoverTokens(purchaser);

        leftoverAmountOf[purchaser] = allocatedLeftover;  
        leftoverDistributed[purchaser] = true;                         // leftover distributed
        purchaserLeftoverDistCount++;                                  // purchaser leftover portion processed
        remaining -= allocatedLeftover;   

        if (allocatedLeftover > 0) {
            token.transfer(purchaser, allocatedLeftover);                  // Finally transfer the leftover tokens
            LeftoverTokenDistributed(purchaser, allocatedLeftover);        // signal the event for communication
        }
        
        if (!hasLeftoverTokens() || remaining < minFtxPurchase || purchaserLeftoverDistCount >= purchaserCount) {
            if (remaining >= token.token4Gas()) {
                token.transfer(owner, remaining);                              // Balance everything out
                LeftoverTokenDistributed(owner,remaining);                     // signal the event for communication
            }
            else {
                // odd case of left over < allowed token transfer minimum, what to do ?
            }
        }
    }

    /*
        return true if there is significant unsold tokens remaining.
    */
    function hasLeftoverTokens() public view returns (bool) {
        return ((tokenHardCap - tokensSold) / purchaserCount) > minFtxPurchase;     // Too small don't care
    }
}