pragma solidity ^0.4.18;

import './math/SafeMath.sol';
import "./ownership/Ownable.sol";
import "./Pausable.sol";
import "./HasNoTokens.sol";
import "./FTXPrivatePresale.sol";

contract FTXPublicPresale is Ownable, Pausable, HasNoTokens {
    using SafeMath for uint256;

    string public constant NAME = "FintruX PublicPresale";
    string public constant VERSION = "0.5";

    FTXPrivatePresale privatePresale;

    // this multi-sig address will be replaced on production:
    address public constant FINTRUX_WALLET = 0xA2d0B62c3d3cBee17f116828ca895Ac5a115bA4a;

    uint256 public publicStartDate = 1515344400;                                    // January 7, 2018 5:00 PM UTC
    uint256 public publicEndDate = 1516554000;                                      // January 21, 2018 5:00 PM UTC

    uint256 public softcapDuration = 2 days;                                        // end earlier when soft-cap reached

    uint256 public weiRaised = 0;                                                   // total amount of Ether raised in wei
    uint256 public purchaserCount = 0;                                              // total number of purchasers purchased FTX
    uint256 public tokensSold = 0;                                                  // total number of FTX tokens sold
    uint256 public numWhitelisted = 0;                                              // total number whitelisted

    /* if the minimum funding goal in token is not reached, purchasers may withdraw their funds */
    uint256 public constant PRESALE_TOKEN_SOFT_CAP = 8250000 * 10**18;              // presale ends 48 hours after soft cap of 8,250,000 FTX is reached
    uint256 public constant PRESALE_RATE = 1650;                                    // presale price is 1 ETH to 1,650 FTX
    uint256 public constant SOFTCAP_RATE = 1575;                                    // presale price becomes 1 ETH to 1,575 FTX after softcap is reached
    uint256 public constant TOKEN_HARD_CAP = 75000000 * 10**18;                     // hardcap is 75% of all tokens
    uint256 public constant MIN_PURCHASE = 10**17;                                  // minimum purchase is 0.1 ETH to make the gas worthwhile
    uint256 public constant MIN_FTX_PURCHASE = 150 * 10**18;                        // minimum token purchase is 150 or 0.1 ETH

    uint256 public presaleWeiRaised = 0;                                            // amount of Ether raised in presales in wei
    uint256 public presaleTokensSold = 0;                                           // number of FTX tokens sold in presales
    uint256 public privatePresaleFTXSold = 0;                                       // number of FTX sold in private presale

    bool public isFinalized = false;                                                // it becomes true when token sale is completed
    bool public publicSoftCapReached = false;                                       // it becomes true when public softcap is reached

    /** the amount of ETH in wei each address has purchased in this crowdsale */
    mapping (address => uint256) public purchasedAmountOf;

    /** the amount of tokens this crowdsale has credited for each purchaser address */
    mapping (address => uint256) public tokenAmountOf;

    address[] public purchasers;                                                     // purchaser wallets

    // list of addresses that can purchase
    mapping (address => bool) public whitelist;

    // contract creation time
    uint private contractTimestamp;
    /**
    * event for token purchase logging
    * @param purchaser who paid for the tokens
    * @param value weis paid for purchase
    * @param amount amount of tokens purchased
    */ 
    event TokenPurchase(address indexed purchaser, uint256 value, uint256 amount);
    
    event Finalized();                                                              // event logging for token sale finalized
    event SoftCapReached();                                                         // event logging for softcap reached
    event FundsTransferred();                                                       // event logging for funds transfered to FintruX multi-sig wallet
    event Refunded(address indexed beneficiary, uint256 weiAmount);                 // event logging for each individual refunded amount

    /*
        Constructor to initialize everything.
    */
    function FTXPublicPresale (address _privatePresale, address _owner) public {
        require(_owner != address(0));
        owner = _owner;                                                             // default owner
        privatePresale = FTXPrivatePresale(_privatePresale);
        privatePresaleFTXSold = privatePresale.tokensSold();                        // number of FTX sold in private presale
        presaleTokensSold = privatePresaleFTXSold;                                  // initialize to FTX sold in private presale
        purchaserCount = privatePresale.purchaserCount();                           // initialize to all presales purchaser count
        tokensSold = privatePresaleFTXSold;                                         // initialize to FTX sold in private presale
        numWhitelisted = privatePresale.numWhitelisted();
        contractTimestamp = block.timestamp;
    }
    
    /*
        Allow changes for public presale dates for testing as well as unforseen changes.
    */
    function setPublicPresaleDates(uint256 newStartDate, uint256 newEndDate) external onlyOwner {
        publicStartDate = newStartDate;
        publicEndDate = newEndDate;
    }

    /*
        add the ether address to whitelist to enable purchase of token.
    */
    function addToWhitelist(address buyer) external onlyOwner {
        require(buyer != address(0));
        
        if (!isWhitelisted(buyer)) {
            whitelist[buyer] = true;
            numWhitelisted += 1;
        }
    }

    /*
        remove the ether address from whitelist in case a mistake was made.
    */
    function delFrWhitelist(address buyer) external onlyOwner {
        require(buyer != address(0));                                               // Valid address
        require(tokenAmountOf[buyer] <= 0);                                         // No purchase yet in the round.

        if (whitelist[buyer]) {
            delete whitelist[buyer];
            numWhitelisted -= 1;
        }
    }
    
    // return true if buyer is whitelisted
    function isWhitelisted(address buyer) public view returns (bool) {
        return whitelist[buyer] || privatePresale.isWhitelisted(buyer);
    }

    function purchasePresale() internal {
        uint256 tokens = 0;
        // still under soft cap
        if (!publicSoftCapReached) {
            tokens = msg.value * PRESALE_RATE;                                      // 1 ETH for 1,100 FTX
            if (presaleTokensSold + tokens > PRESALE_TOKEN_SOFT_CAP) {              // get less if over softcap
                uint256 availablePresaleTokens = PRESALE_TOKEN_SOFT_CAP - presaleTokensSold;
                uint256 softCapTokens = (msg.value - (availablePresaleTokens / PRESALE_RATE)) * SOFTCAP_RATE;
                tokens = availablePresaleTokens + softCapTokens;
                processSale(tokens, SOFTCAP_RATE);                                  // process presale at 1 ETH to 1,050 FTX
                publicSoftCapReached = true;                                        // public soft cap has been reached
                publicEndDate = now + softcapDuration;                              // shorten the presale cycle
                SoftCapReached();                                                   // signal the event for communication
            } else {
                processSale(tokens, PRESALE_RATE);                                  // process presale @PRESALE_RATE
            }
        } else {
            tokens = msg.value * SOFTCAP_RATE;                                      // 1 ETH to 1,575 FTX
            processSale(tokens, SOFTCAP_RATE);                                      // process presale at 1 ETH to 1,575 FTX
        }
        presaleTokensSold += tokens;                                                // update presale ETH raised
        presaleWeiRaised += msg.value;                                              // update presale FTX sold
    }

    /*
        process sale at determined price.
    */
    function processSale(uint256 ftx, uint256 ftxRate) internal {
        uint256 ftxOver = 0;
        uint256 excessEthInWei = 0;
        uint256 paidValue = msg.value;

        if (tokensSold + ftx > TOKEN_HARD_CAP) {                                    // if maximum is exceeded
            ftxOver = tokensSold + ftx - TOKEN_HARD_CAP;                            // find overage
            excessEthInWei = ftxOver/ftxRate;                                       // overage ETH to refund
            ftx = ftx - ftxOver;                                                    // adjust tokens purchased
            paidValue = paidValue - excessEthInWei;                                 // adjust Ether paid
        }
        if (tokenAmountOf[msg.sender] == 0 && privatePresale.tokenAmountOf(msg.sender) == 0) {
            purchaserCount++;                                                       // count new purchasers
            purchasers.push(msg.sender);
        }
        tokenAmountOf[owner] = tokenAmountOf[owner].sub(ftx);                           // deduct FTX from Fintrux account
        tokenAmountOf[msg.sender] = tokenAmountOf[msg.sender].add(ftx);                 // record FTX on purchaser account
        purchasedAmountOf[msg.sender] = purchasedAmountOf[msg.sender].add(paidValue);   // record ETH paid
        weiRaised += paidValue;                                                         // total ETH raised
        tokensSold += ftx;                                                              // total FTX sold
        TokenPurchase(msg.sender, paidValue, ftx);                                      // signal the event for communication
        // transfer must be done at the end after all states are updated to prevent reentrancy attack.
        if (excessEthInWei > 0) {
            msg.sender.transfer(excessEthInWei);                                       // refund overage ETH
            Refunded(msg.sender, excessEthInWei);                                      // signal the event for communication
        }
    }

    /*
       default function to buy tokens.
    */
    function () payable public whenNotPaused {
        require(isPublicPresale());
        require(!hasSoldOut());                                                     // stop if no more token is allocated for sale
        require(msg.sender != address(0));                                          // stop if address not valid
        require(msg.value >= MIN_PURCHASE);                                         // stop if the purchase is too small
        require(isWhitelisted(msg.sender));                                         // no purchase unless whitelisted

        purchasePresale();                                                          // do public presale
    }

    /*
        Check to see if this is public presale.
    */
    function isPublicPresale() public view returns (bool) {
        return !isFinalized && now >= publicStartDate && now <= publicEndDate;
    }

    /*
        check if allocated has sold out.
    */
    function hasSoldOut() public view returns (bool) {
        return TOKEN_HARD_CAP - tokensSold < MIN_FTX_PURCHASE;
    }

    /*
        Check to see if the crowdsale end date has passed or if all tokens allocated for sale has been purchased.
    */
    function hasEnded() public view returns (bool) {
        return now > publicEndDate || hasSoldOut();
    }

    /*
        Called after public presale ends, to do some extra finalization work.
    */
    function finalize() public onlyOwner {
        require(!isFinalized);                                                      // do nothing if finalized
        require(hasEnded());                                                        // sales ended
        FINTRUX_WALLET.transfer(this.balance);                                      // transfer to FintruX multisig wallet
        FundsTransferred();                                                         // signal the event for communication
        isFinalized = true;                                                         // mark as finalized
        Finalized();                                                                // signal the event for communication
    }

    /* recovery option if things go wrong, only available after 2 years of contract deployment */
    function recoveryEth(address beneficiary) public onlyOwner {
        require(beneficiary != address(0));
        require(now > contractTimestamp + 2 years);
        beneficiary.transfer(this.balance);
    }

    /*
        Corwdsale Dapp calls these helper functions.
    */
    function isSaleActive() public view returns (bool) {
        return isPublicPresale() && !hasEnded();                                    // return true if sales is on
    }

    /*
        For the convenience of crowdsale interface to find current discount tier.
    */
    function getTier() public view returns (uint256) {
        uint256 tier = 1;                                                           // Assume presale top tier discount
        if (now >= publicStartDate && now < publicEndDate) {
            if (getSoftCapReached()) {
                tier = 2;                                                       // tier 2 discount
            }
        }
        return tier;
    }

    /*
        For the convenience of crowdsale interface to present status info.
    */
    function getSoftCapReached() public view returns(bool) {
        return publicSoftCapReached;
    }

    /*
        For the convenience of crowdsale interface to present status info.
    */
    function getCrowdSaleStatus() public view returns(uint256[3]) {
        // 0 - presale not started
        // 1 - private presale started
        // 2 - private presale ended, public presale not started
        // 3 - presale started (public)
        // 4 - presale ended (private/public), crowsale not started
        // 5 - crowsale started
        // 6 - crowsale ended
        if (now < publicStartDate) {
            return([2,publicStartDate,publicEndDate]);
        } else if (now <= publicEndDate) {
            return([3,publicStartDate,publicEndDate]);
        } else {
            return([4,publicStartDate,publicEndDate]);
        }
    }
}