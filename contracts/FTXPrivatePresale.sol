pragma solidity ^0.4.18;

import './math/SafeMath.sol';
import "./ownership/Ownable.sol";
import "./Pausable.sol";
import "./HasNoTokens.sol";

contract FTXPrivatePresale is Ownable, Pausable, HasNoTokens {
    using SafeMath for uint256;

    string public constant NAME = "FintruX PrivatePresale";
    string public constant VERSION = "0.6";

    uint256 public privateStartDate = 1513270800;                                   // Dec 14, 2017 5:00 PM UTC
    uint256 public privateEndDate = 1515258000;                                     // Jan 6, 2018 5:00 PM UTC

    uint256 public purchaserCount = 0;                                              // total number of purchasers purchased FTX
    uint256 public tokensSold = 0;                                                  // total number of FTX tokens sold
    uint256 public numWhitelisted = 0;                                              // total number whitelisted

    uint256 public constant TOKEN_HARD_CAP = 0.1 * 100000000 * 10**18;              // hardcap is 10% of all tokens
    uint256 public constant MIN_FTX_PURCHASE = 1 * 1500 * 10**18;                   // minimum token purchase is 1 ETH(@1500)

    bool public isFinalized = false;                                                // it becomes true when token sale is completed

    /** the amount of tokens this crowdsale has credited for each purchaser address */
    mapping (address => uint256) public tokenAmountOf;

    address[] public purchasers;                                                     // purchaser wallets

    // list of addresses that can purchase
    mapping (address => bool) public whitelist;

    /**
    * event for token purchase logging
    * @param purchaser who paid for the tokens
    * @param value weis paid for purchase
    * @param amount amount of tokens purchased
    */ 
    event TokenPurchase(address indexed purchaser, uint256 value, uint256 amount);
    
    event Finalized();                                                              // event logging for token sale finalized

    /*
        Constructor to initialize everything.
    */
    function FTXPrivatePresale (address _owner) public {
        if (_owner == address(0)) {
            _owner = msg.sender;
        }
        require(_owner != address(0));
        owner = _owner;                                                             // default owner
    }

    /*
        Allow changes for private presale dates for testing as well as unforseen changes.
    */
    function setPrivatePresaleDates(uint256 newStartDate, uint256 newEndDate) external onlyOwner {
        privateStartDate = newStartDate;
        privateEndDate = newEndDate;
    }

    /*
        add the ether address to whitelist to enable purchase of token.
    */
    function addToWhitelist(address buyer) external onlyOwner {
        require(buyer != address(0));
        require(!isWhitelisted(buyer));
        
        whitelist[buyer] = true;
        numWhitelisted += 1;
    }

    /*
        remove the ether address from whitelist in case a mistake was made.
    */
    function delFrWhitelist(address buyer) external onlyOwner {
        require(buyer != address(0));                                               // Valid address
        require(tokenAmountOf[buyer] <= 0);                                         // No token purchase yet.
        require(whitelist[buyer]);
        delete whitelist[buyer];
        numWhitelisted -= 1;
    }
    
    // return true if buyer is whitelisted
    function isWhitelisted(address buyer) public view returns (bool) {
        return whitelist[buyer];
    }

    /*
        process sale.
    */
    function processSale(address buyer, uint256 ftx) internal {
        require(tokensSold + ftx <= TOKEN_HARD_CAP);                                // if maximum is exceeded
        if (tokenAmountOf[buyer] == 0) {
            purchaserCount++;                                                       // count new purchasers
            purchasers.push(buyer);
        }
        tokenAmountOf[buyer] = tokenAmountOf[buyer].add(ftx);                       // record FTX on purchaser account
        // do not record ETH/Fiat paid:
        tokensSold += ftx;                                                          // total FTX sold
        TokenPurchase(buyer, msg.value, ftx);                                       // signal the event for communication
    }

    /*
        buy token via fiat currency or crypto.
    */
    function payableInFiatEth(address buyer, uint256 ftx) external onlyOwner {
        require(isPrivatePresale());                                                // Only contribute during private presale
        require(!hasSoldOut());                                                     // stop if no more token is allocated for sale
        require(isWhitelisted(buyer));                                              // no purchase unless whitelisted
        require(ftx >= MIN_FTX_PURCHASE);                                           // no micro token purchase
        processSale(buyer, ftx);                                                    // do private presale in fiat/ETH
    }

    /*
        Check to see if this is private presale.
    */
    function isPrivatePresale() public view returns (bool) {
        return !isFinalized && now >= privateStartDate && now <= privateEndDate;
    }

    /*
        check if allocated has sold out.
    */
    function hasSoldOut() public view returns (bool) {
        return TOKEN_HARD_CAP - tokensSold <= 0;
    }

    /*
        Check to see if the crowdsale end date has passed or if all tokens allocated for sale has been purchased.
    */
    function hasEnded() public view returns (bool) {
        return now > privateEndDate || hasSoldOut();
    }

    /*
        Called after private presale ends, to do some extra finalization work.
    */
    function finalize() public onlyOwner {
        require(!isFinalized);                                                      // do nothing if finalized
        require(hasEnded());                                                        // privare presale must have ended
        // not need to transfer to FintruX multisig wallet because fiat/eth will be direct deposit.
        isFinalized = true;                                                         // mark as finalized
        Finalized();                                                                // signal the event for communication
    }

    /*
        Corwdsale Dapp calls these helper functions.
    */
    function isSaleActive() public view returns (bool) {
        return isPrivatePresale() && !hasSoldOut();                                   // return true if sales is on
    }
}