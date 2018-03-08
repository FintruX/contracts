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
    string public constant VERSION = "0.9";

    // this Fintrux address will be replaced on production:
    address public constant FINTRUX_WALLET = 0x7c05c62ae365E88221B62cA41D6eb087fDAa2020;

    // this private sale address will be replaced on production; it has zero balance and need to be treated as full:
    address public constant PRIVATE_WALLET = 0x7c05c62ae365E88221B62cA41D6eb087fDAa2020;

    FTXPrivatePresale   privatePresale;                                             // private pre-sale contract
    FTXPublicPresale    publicPresale;                                              // public pre-sale contract
    FTXSale             crowdSale;                                                  // public token sale contract
    FTXToken            token;                                                      // token contract

    uint256 public purchaserCount = 0;                                              // total number of purchasers purchased FTX
    uint256 public purchaserLeftoverClaimedCount = 0;                               // total number of purchasers received(may be zero) leftover portion
    uint256 public tokensSold = 0;                                                  // tokens sold from private presale + public presale + crowdsale
    uint256 public tokensToDistribute = 0;                                          // leftover tokens to be distributed in this batch
    uint256 public tokensRemaining = 0;                                             // leftover tokens remaining to take care of rounding issues

    /** the amount of leftover tokens this crowdsale has distributed for each purchaser address */
    mapping (address => uint256) public leftoverAmountOf;

    /** this becomes true when leftover tokens has been distributed for each purchaser address */
    mapping (address => bool) public leftoverDistributed;

    /** this becomes true when leftover tokens has been claimed for each purchaser address */
    mapping (address => bool) public leftoverClaimed;

    event LeftoverTokenClaimed(address indexed purchaser, uint256 tokenAmt);        // event logging for each individual leftover claimed

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
        tokensRemaining = _tokensToDistribute;                                      // initialize remaining to total of this batch
        require(token.balanceOf(address(owner)) >= tokensToDistribute);             // just in case of input error

        privatePresale = FTXPrivatePresale(_privatePresale);
        publicPresale = FTXPublicPresale(_publicPresale);
        crowdSale = FTXSale(_crowdsale);
        purchaserCount = crowdSale.purchaserCount();                                // initialize to all purchaser count
        tokensSold = crowdSale.tokensSold();                                        // initialize token sold from crowd sale
    }

    /*
        Call from DAPP to distribute ALL leftover tokens at the same time to all purchasers at the announced time.
    */
    function distributeLeftover(address purchaser) external onlyOwner {
        require(crowdSale.isFinalized());
        require(!leftoverDistributed[purchaser]);                                   // distribute once only
        require(token != address(0));
        require(token.balanceOf(address(this)) > 0);                                // must not be empty

        uint256 allocatedLeftover = 0;
        uint256 fintruxLeftover = 0;
        uint256 tokenPurchased = crowdSale.tokenAmountOf(purchaser) + privatePresale.tokenAmountOf(purchaser) + publicPresale.tokenAmountOf(purchaser);
        uint256 tokenHodl = token.balanceOf(purchaser);                             // Hodl amount of purchased tokens

        // Distribute leftover tokens proporationally if not fully sold.
        allocatedLeftover = (tokenPurchased * tokensToDistribute) / tokensSold;
        if (tokensRemaining < allocatedLeftover) {                                  // In case not enough remaining
            allocatedLeftover = tokensRemaining;
        }
        tokensRemaining -= allocatedLeftover;                                       // update remaining tokens

        if (purchaser != PRIVATE_WALLET && tokenHodl < tokenPurchased) {            // purchasers get less if not hodl (except private sale)
            fintruxLeftover = allocatedLeftover * ((tokenPurchased - tokenHodl) / tokenPurchased);
            allocatedLeftover = allocatedLeftover - fintruxLeftover;
        }
        if (allocatedLeftover < token.token4Gas()) {                                // too small, given them zero
            leftoverAmountOf[FINTRUX_WALLET] += allocatedLeftover;                  // make the best use of it.
            allocatedLeftover = 0;
        }
        leftoverAmountOf[FINTRUX_WALLET] += fintruxLeftover;                        // assign left over to fintrux
        leftoverDistributed[purchaser] = true;                                      // leftover distributed
        leftoverAmountOf[purchaser] = allocatedLeftover;                            // assign left over to purchaser
    }

    /*
        Call from DAPP. Send leftover tokens to this purchaser when claimed.
    */
    function claimLeftover(address purchaser) external onlyOwner {
        require(token != address(0));
        require(token.balanceOf(address(this)) > 0);                            // must not be empty
        require(!leftoverClaimed[purchaser]);                                   // claime once only

        leftoverClaimed[purchaser] = true;                                      // leftover claimed
        purchaserLeftoverClaimedCount++;                                        // purchaser leftover portion processed
        if (leftoverAmountOf[purchaser] > 0) {
            token.transfer(purchaser, leftoverAmountOf[purchaser]);             // Finally transfer the leftover tokens
            LeftoverTokenClaimed(purchaser, leftoverAmountOf[purchaser]);       // signal the event for communication
        }
    }
}