pragma solidity ^0.4.18;

import './math/SafeMath.sol';
import "./FTXToken.sol";
import "./ownership/Ownable.sol";
import "./HasNoTokens.sol";
import "./FTXPrivatePresale.sol";
import "./FTXPublicPresale.sol";
import "./FTXSale.sol";

contract FTXPurchase is Ownable, HasNoTokens {
    using SafeMath for uint256;

    string public constant NAME = "FintruX purchased tokens distribution";
    string public constant VERSION = "0.8";

    FTXToken            token;
    FTXPrivatePresale   privatePresale;
    FTXPublicPresale    publicPresale;
    FTXSale             crowdSale;

    uint256 public purchaserCount = 0;                                              // total number of purchasers purchased FTX
    uint256 public purchaserDistCount = 0;                                          // total number of purchasers received purchased FTX + bonus
    uint256 public tokensSold = 0;                                                  
    uint256 public minFtxPurchase = 0;
    uint256 public tokenHardCap = 0;
    /** this becomes true when crowdsale has distributed purchased tokens with bonus for each purchaser address */
    mapping (address => bool) public tokenDistributed;

    event TokenDistributed(address indexed purchaser, uint256 tokenAmt);            // event logging for each individual distributed token + bonus

    /*
        Prerequisites:  1. crowdsale has finalized prior to this deployment; and
                        2. redo token contract if it had been used by any prior deployment of this.
        Constructor to initialize everything.
    */
    function FTXPurchase (address _privatePresale, address _publicPresale, address _crowdsale, address _token, address _owner) public {
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

    /*
        Distribute tokens purchased with bonus.
    */
    function distributeTokensFor(address purchaser) external onlyOwner {
        require(token != address(0));
        require(crowdSale.isFinalized());
        //require(crowdSale.isMinimumGoalReached());
        require(!tokenDistributed[purchaser]);
        tokenDistributed[purchaser] = true;                                         // token + bonus distributed
        uint256 tokenPurchased = crowdSale.tokenAmountOf(purchaser) + privatePresale.tokenAmountOf(purchaser) + publicPresale.tokenAmountOf(purchaser);
        purchaserDistCount++;                                                       // one more purchaser received token + bonus
        // transfer the purchased tokens + bonus
        token.transfer(purchaser, tokenPurchased);
        // signal the event for communication
        TokenDistributed(purchaser, tokenPurchased);
    }
}