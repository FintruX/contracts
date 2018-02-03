pragma solidity ^0.4.18;

import './math/SafeMath.sol';
import "./FTXToken.sol";
import "./ownership/Ownable.sol";
import "./HasNoTokens.sol";
import "./FTXPrivatePresale.sol";
import "./FTXPublicPresale.sol";
import "./FTXSale.sol";

contract FTXLeftover is Ownable, HasNoTokens {
    using SafeMath for uint256;

    string public constant NAME = "FintruX leftover tokens distribution";
    string public constant VERSION = "0.8";

    FTXPrivatePresale   privatePresale;                                             // private pre-sale contract
    FTXPublicPresale    publicPresale;                                              // public pre-sale contract
    FTXSale             crowdSale;                                                  // public token sale contract
    FTXToken            token;                                                      // token contract

    uint256 public purchaserCount = 0;                                              // total number of purchasers purchased FTX
    uint256 public purchaserLeftoverDistCount = 0;                                  // total number of purchasers received(may be zero) leftover portion
    uint256 public tokensSold = 0;                                                  // tokens sold from private presale + public presale + crowdsale
    uint256 public tokensToDistribute = 0;                                          // leftover tokens to be distributed in this batch

    /** the amount of leftover tokens this crowdsale has distributed for each purchaser address */
    mapping (address => uint256) public leftoverAmountOf;

    /** this becomes true when crowdsale has distributed leftover tokens for each purchaser address */
    mapping (address => bool) public leftoverDistributed;

    event LeftoverTokenDistributed(address indexed purchaser, uint256 tokenAmt);    // event logging for each individual distributed leftover

    /*
        Prerequisites: purchased tokens have been distributed prior to this deployment;
        Constructor to initialize everything. Any permanently unclaimed tokens will be considered burnt.
    */
    function FTXLeftover (address _privatePresale, address _publicPresale, address _crowdsale, address _token, address _owner, uint256 _tokensToDistribute) public {
        if (_owner == address(0)) {
            _owner = msg.sender;
        }
        require(_privatePresale != address(0));
        require(_publicPresale != address(0));
        require(_crowdsale != address(0));
        require(_owner != address(0));                
        require(_tokensToDistribute > 0);
        token = FTXToken(_token);
        owner = _owner;                                                             // default owner
        tokensToDistribute = _tokensToDistribute;                                   // leftover tokens to be distributed in this batch
        require(token.balanceOf(address(owner)) >= tokensToDistribute);             // just in case of input error

        privatePresale = FTXPrivatePresale(_privatePresale);
        publicPresale = FTXPublicPresale(_publicPresale);
        crowdSale = FTXSale(_crowdsale);
        purchaserCount = crowdSale.purchaserCount();                                // initialize to all purchaser count
        tokensSold = crowdSale.tokensSold();                                        // initialize token sold from crowd sale
    }

    /*
        Calculate leftover token for each purchaser. Keep it public so it can be called from DAPP. 
    */
    function calcLeftoverTokens(address purchaser) public view returns (uint256) {
        uint256 allocatedLeftover = 0;
        uint256 remaining = token.balanceOf(address(this));
        uint256 tokenPurchased = crowdSale.tokenAmountOf(purchaser) + privatePresale.tokenAmountOf(purchaser) + publicPresale.tokenAmountOf(purchaser);
        // Send leftover tokens out proporationally if not fully sold.
        allocatedLeftover = (tokenPurchased * tokensToDistribute) / tokensSold;
        /* The following would only function properly in the actual distribution, not in estimation */
        if (remaining < allocatedLeftover) {                            // In case not enough remaining
            allocatedLeftover = remaining;
        }
        if (allocatedLeftover < token.token4Gas()) {                    // too small, given them zero
            allocatedLeftover = 0;
        }
        return allocatedLeftover;
    }

    /*
        Distribute leftover tokens one time.
    */
    function distributeLeftoverForOne(address purchaser) internal {
        require(token != address(0));
        require(crowdSale.isFinalized());
        require(!leftoverDistributed[purchaser]);                           // distribute once only
        require(token.balanceOf(address(this)) > 0);                        // must not be empty

        uint256 allocatedLeftover = 0;
        // Calculate leftover tokens proporationally if not fully sold.
        allocatedLeftover = calcLeftoverTokens(purchaser);

        leftoverAmountOf[purchaser] = allocatedLeftover;  
        leftoverDistributed[purchaser] = true;                              // leftover distributed
        purchaserLeftoverDistCount++;                                       // purchaser leftover portion processed

        if (allocatedLeftover > 0) {
            token.transfer(purchaser, allocatedLeftover);                   // Finally transfer the leftover tokens
            LeftoverTokenDistributed(purchaser, allocatedLeftover);         // signal the event for communication
        }
    }

    /*
        Call from DAPP. Distribute leftover tokens to this purchaser when claimed.
    */
    function distributeLeftover(address purchaser) external onlyOwner {
        distributeLeftoverForOne(purchaser);
    }
}