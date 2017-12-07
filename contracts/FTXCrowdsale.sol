pragma solidity ^0.4.18;

import './math/SafeMath.sol';
import "./FTXToken.sol";
import "./ownership/Ownable.sol";
import "./Pausable.sol";
import "./HasNoTokens.sol";

contract FTXCrowdsale is Ownable, Pausable, HasNoTokens {
    using SafeMath for uint256;

    string public constant NAME = "FintruX Crowdsale";
    string public constant VERSION = "0.4";

    FTXToken token;

    // this multi-sig address will be replaced on production:
    address public constant FINTRUX_WALLET = 0xA2d0B62c3d3cBee17f116828ca895Ac5a115bA4a;

    uint256 public privateStartDate = 1513270800;                                   // Dec 14, 2017 5:00 PM UTC
    uint256 public privateEndDate = 1514480400;                                     // Dec 28, 2017 5:00 PM UTC

    uint256 public publicStartDate = 1515344400;                                    // January 7, 2018 5:00 PM UTC
    uint256 public publicEndDate = 1516554000;                                      // January 21, 2018 5:00 PM UTC

    uint256 public startDate = 1518022800;                                          // Feb 7, 2017 5:00 PM UTC
    uint256 public endDate = 1519837200;                                            // Feb 28, 2017 5:00 PM UTC

    uint256 public softcapDuration = 2 days;                                        // end earlier when soft-cap reached

	struct TokenDiscount {
		uint256 tokensAvail;                                                        // total tokens available at this price
		uint256 tokensSold;                                                         // tokens sold at this price
		uint256 tokenPrice;                                                         // number of tokens per ETH
	}
	TokenDiscount[5] public tokenDiscount;

    uint256 public weiRaised = 0;                                                   // total amount of Ether raised in wei
    uint256 public purchaserCount = 0;                                              // total number of purchasers purchased FTX
    uint256 public purchaserDistCount = 0;                                          // total number of purchasers received purchased FTX + bonus
    uint256 public tokensSold = 0;                                                  // total number of FTX tokens sold
    uint256 public NumWhitelisted = 0;                                              // total number whitelisted

    /* if the minimum funding goal in wei is not reached, purchasers may withdraw their funds */
    uint256 public constant MIN_FUNDING_GOAL = 5000 * 10**18;

    uint256 public constant PRESALE_TOKEN_SOFT_CAP = 8250000 * 10**18;              // presale ends 48 hours after soft cap of 8,250,000 FTX is reached
    uint256 public constant PRESALE_RATE = 1650;                                    // presale price is 1 ETH to 1,650 FTX
    uint256 public constant SOFTCAP_RATE = 1575;                                    // presale price becomes 1 ETH to 1,575 FTX after softcap is reached
    uint256 public constant TOKEN_HARD_CAP = 75000000 * 10**18;                     // hardcap is 75% of all tokens
    uint256 public constant MIN_PURCHASE = 10**17;                                  // minimum purchase is 0.1 ETH to make the gas worthwhile
    uint256 public constant MIN_FTX_PURCHASE = 150 * 10**18;                        // minimum token purchase is 150 or 0.1 ETH

    uint256 public presaleWeiRaised = 0;                                            // amount of Ether raised in presales in wei
    uint256 public presaleTokensSold = 0;                                           // number of FTX tokens sold in presales

    bool public isFinalized = false;                                                // it becomes true when token sale is completed
    bool public privateSoftCapReached = false;                                      // it becomes true when private softcap is reached
    bool public publicSoftCapReached = false;                                       // it becomes true when public softcap is reached

    /** the amount of ETH in wei each address has purchased in this crowdsale */
    mapping (address => uint256) public purchasedAmountOf;

    /** the amount of tokens this crowdsale has credited for each purchaser address */
    mapping (address => uint256) public tokenAmountOf;

    /** this becomes true when crowdsale has distributed purchased tokens with bonus for each purchaser address */
    mapping (address => bool) public tokenDistributed;

    /** the amount of leftover tokens this crowdsale has distributed for each purchaser address */
    mapping (address => uint256) public leftoverAmountOf;

    /** this becomes true when crowdsale has distributed leftover tokens for each purchaser address */
    mapping (address => bool) public leftoverDistributed;

    address[] public purchasers;                                                     // purchaser wallets

    // list of addresses that can purchase
    mapping (address => bool) public whitelist;

    /**
    * event for token purchase logging
    * @param purchaser who paid for the tokens
    * @param beneficiary who got the tokens
    * @param value weis paid for purchase
    * @param amount amount of tokens purchased
    */ 
    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);
    
    event Finalized();                                                              // event logging for token sale finalized
    event SoftCapReached();                                                         // event logging for softcap reached
    event FundsTransferred();                                                       // event logging for funds transfered to FintruX multi-sig wallet
    event Refunded(address indexed beneficiary, uint256 weiAmount);                 // event logging for each individual refunded amount
    event TokenDistributed(address indexed purchaser, uint256 tokenAmt);            // event logging for each individual distributed token + bonus
    event LeftoverTokenDistributed(address indexed purchaser, uint256 tokenAmt);    // event logging for each individual distributed leftover

    /*
        Constructor to initialize everything.
    */
    function FTXCrowdsale (address _token, address _owner) public {
        require(_token != address(0));
        require(_owner != address(0));
        token = FTXToken(_token);
        owner = _owner;                                                             // default owner

        tokenAmountOf[owner] = TOKEN_HARD_CAP;                                      // maximum tokens to be sold

        // bonus tiers
        tokenDiscount[0] = TokenDiscount(3150000 * 10**18, 0, 1575);                // 5.0% bonus
        tokenDiscount[1] = TokenDiscount(5383000 * 10**18, 0, 1538);                // 2.5% bonus
        tokenDiscount[2] = TokenDiscount(10626000 * 10**18, 0, 1518);               // 1.2% bonus
        tokenDiscount[3] = TokenDiscount(18108000 * 10**18, 0, 1509);               // 0.6% bonus
        tokenDiscount[4] = TokenDiscount(37733000 * 10**18, 0, 1500);               // base price
    }

/*
Remove the following three functions before production. only for scripted testing use, must not be part of the contract in production
*/
function setPrivateDates(uint256 newStartDate, uint256 newEndDate) public onlyOwner {
privateStartDate = newStartDate;
privateEndDate = newEndDate;
}
function setPublicDates(uint256 newStartDate, uint256 newEndDate) public onlyOwner {
publicStartDate = newStartDate;
publicEndDate = newEndDate;
}
function setDates(uint256 newStartDate, uint256 newEndDate) public onlyOwner {
startDate = newStartDate;
endDate = newEndDate;
}
/* end of testing helper functions */

    /*
        add the ether address to whitelist to enable purchase of token.
    */
    function addToWhitelist(address buyer) external onlyOwner {
        require(buyer != address(0));
        
        if (!isWhitelisted(buyer)) {
            whitelist[buyer] = true;
            NumWhitelisted += 1;
        }
    }

    /*
        remove the ether address from whitelist in case a mistake was made.
    */
    function delFrWhitelist(address buyer) public onlyOwner {
        require(buyer != address(0));                                               // Valid address
        require(purchasedAmountOf[buyer] <= 0);                                      // No purchase yet.

        if (isWhitelisted(buyer)) {
            delete whitelist[buyer];
            NumWhitelisted -= 1;
        }
    }
    
    // return true if buyer is whitelisted
    function isWhitelisted(address buyer) public view returns (bool) {
        return whitelist[buyer];
    }

    function purchasePresale(bool bPrivate) internal {
        uint256 tokens = 0;
        // still under soft cap
        if ((bPrivate && !privateSoftCapReached) || (!bPrivate && !publicSoftCapReached)) {
            tokens = msg.value * PRESALE_RATE;                                      // 1 ETH for 1,100 FTX
            if (presaleTokensSold + tokens > PRESALE_TOKEN_SOFT_CAP) {             // get less if over softcap
                uint256 availablePresaleTokens = PRESALE_TOKEN_SOFT_CAP - presaleTokensSold;
                uint256 softCapTokens = (msg.value - (availablePresaleTokens / PRESALE_RATE)) * SOFTCAP_RATE;
                tokens = availablePresaleTokens + softCapTokens;
                processSale(tokens, SOFTCAP_RATE);                                  // process presale at 1 ETH to 1,050 FTX
                if (bPrivate) {                                             
                    privateSoftCapReached = true;                                   // private soft cap has been reached
                    privateEndDate = now + softcapDuration;                         // shorten the presale cycle
                } else {
                    publicSoftCapReached = true;                                    // public soft cap has been reached
                    publicEndDate = now + softcapDuration;                          // shorten the presale cycle
                }
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
        perform crowdsale.
    */
    function purchaseCrowdsale() internal {
        uint256 amountTransfered = msg.value; 
        uint256 tokens = 0;
        uint256 currentRate = 0;
        uint256 tokensToBuy;

        // Five tiers of discount:
        for (uint di = 0; di < tokenDiscount.length; di++) {
            TokenDiscount storage ts = tokenDiscount[di];

            // if there are tokens available at that tier and still have leftover ETH
            if (ts.tokensSold < ts.tokensAvail && amountTransfered > 0) {
                tokensToBuy = amountTransfered * ts.tokenPrice;
                if (ts.tokensSold + tokensToBuy > ts.tokensAvail) {
                    tokensToBuy = ts.tokensAvail - ts.tokensSold;
                }
                currentRate = ts.tokenPrice;                                        // current rate FTX per ETH
                tokens += tokensToBuy;                                              // acumulated tokens to buy
                ts.tokensSold += tokensToBuy;
                amountTransfered -= tokensToBuy / ts.tokenPrice;
            }
        }
        processSale(tokens, currentRate);                                          // process crowdsale at determined price
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
        if (tokenAmountOf[msg.sender] == 0) {
            purchaserCount++;                                                       // count new purchasers
            purchasers.push(msg.sender);
        }
        tokenAmountOf[owner] = tokenAmountOf[owner].sub(ftx);                           // deduct FTX from Fintrux account
        tokenAmountOf[msg.sender] = tokenAmountOf[msg.sender].add(ftx);                 // record FTX on purchaser account
        purchasedAmountOf[msg.sender] = purchasedAmountOf[msg.sender].add(paidValue);   // record ETH paid
        weiRaised += paidValue;                                                         // total ETH raised
        tokensSold += ftx;                                                              // total FTX sold
        TokenPurchase(msg.sender, msg.sender, paidValue, ftx);                          // signal the event for communication
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
        require(tokensSold < TOKEN_HARD_CAP);                                       // stop if no more token is allocated for sale
        require(msg.sender != address(0));                                          // stop if address not valid
        require(tokenAmountOf[owner] > 0);                                          // stop if no more token to sell
        require(msg.value >= MIN_PURCHASE);                                         // stop if the purchase is too small
        require(isWhitelisted(msg.sender));                                         // no purchase unless whitelisted

        if (isPrivatePresale()) {
            purchasePresale(true);                                                  // do private presale
        } else if (!privateSoftCapReached && isPublicPresale()) {
            purchasePresale(false);                                                 // do public presale
        } else if (isCrowdsale()) {
            purchaseCrowdsale();                                                    // do crowdsale
        } else {
            revert();                                                               // do nothing
        }
    }

    /*
        Check to see if this is private presale.
    */
    function isPrivatePresale() public view returns (bool) {
        return !isFinalized && now >= privateStartDate && now <= privateEndDate;
    }

    /*
        Check to see if this is public presale.
    */
    function isPublicPresale() public view returns (bool) {
        return !isFinalized && now >= publicStartDate && now <= publicEndDate;
    }

    /*
        Check to see if this is crowdsale.
    */
    function isCrowdsale() public view returns (bool) {
        return !isFinalized && now >= startDate && now <= endDate;
    }

    /*
        Check to see if the crowdsale end date has passed or if all tokens allocated for sale has been purchased.
    */
    function hasEnded() public view returns (bool) {
        return now > endDate || (TOKEN_HARD_CAP - tokensSold < MIN_FTX_PURCHASE);
    }

    /*
        return true if there is significant unsold tokens remaining.
    */
    function hasLeftoverTokens() public view returns (bool) {
        return ((TOKEN_HARD_CAP - tokensSold) / purchaserCount) > MIN_FTX_PURCHASE;     // Too small don't care
    }

    /*
        Determine if the minimum goal in wei has been reached.
    */
    function isMinimumGoalReached() public view returns (bool) {
        return weiRaised >= MIN_FUNDING_GOAL;
    }

    /*
        Called after crowdsale ends, to do some extra finalization work.
    */
    function finalize() public onlyOwner {
        require(!isFinalized);                                                      // do nothing if finalized
        require(hasEnded());                                                        // crowdsale must have ended
        if (isMinimumGoalReached()) {
            FINTRUX_WALLET.transfer(this.balance);                                  // transfer to FintruX multisig wallet
            FundsTransferred();                                                     // signal the event for communication
        }
        isFinalized = true;                                                         // mark as finalized
        Finalized();                                                                // signal the event for communication
    }

    /*
        purchaser requesting a refund if minimum goal not reached.
    */
    function claimRefund() external {
        require(isFinalized && !isMinimumGoalReached());                            // cannot refund unless authorized
        uint256 depositedValue = purchasedAmountOf[msg.sender];                     // ETH to refund
        purchasedAmountOf[msg.sender] = 0;                                          // assume all refunded
        // transfer must be called only after purchasedAmountOf is updated to prevent reentrancy attack.
        msg.sender.transfer(depositedValue);                                        // refund all ETH
        Refunded(msg.sender, depositedValue);                                       // signal the event for communication
    }

    /*
    // Instead of looping here, do the for loop outside in Dapp is better pratice.
    function distributeTokensForAll() public onlyOwner {
        for (uint256 i = 0; i < purchasers.length; i++) {
            distributeTokensFor(purchasers[i]);
        }
    }
    */

    /*
        Distribute tokens purchased with bonus.
    */
    function distributeTokensFor(address purchaser) external onlyOwner {
        require(isFinalized);
        require(isMinimumGoalReached());
        require(!tokenDistributed[purchaser]);                        // distribute once only
        require(token.balanceOf(address(this)) > 0);                  // must not be empty
        tokenDistributed[purchaser] = true;                           // token + bonus distributed
        purchaserDistCount++;                                         // one more purchaser received token + bonus
        token.transfer(purchaser, tokenAmountOf[purchaser]);          // transfer the purchased tokens + bonus
        TokenDistributed(purchaser, tokenAmountOf[purchaser]);        // signal the event for communication

        // clean up the account if all purchasers have received tokens + bonus and there is no unsold tokens
        if (purchaserDistCount >= purchaserCount && !hasLeftoverTokens()) {
            token.transfer(owner, token.balanceOf(address(this)));  // Balance everything out
        }
    }

    /*
        Distribute leftover tokens one time.
    */
    function distributeLeftover(address purchaser) external onlyOwner {
        require(isFinalized);
        require(isMinimumGoalReached());
        require(!leftoverDistributed[purchaser]);                         // distribute once only
        require(token.balanceOf(address(this)) > 0);                      // must not be empty

        uint256 allocatedLeftover = 0;
        uint256 remaining = token.balanceOf(address(this));
        // Send leftover tokens out proporationally if not fully sold.
        if (hasLeftoverTokens()) {
            allocatedLeftover = (tokenAmountOf[purchaser] * (TOKEN_HARD_CAP - tokensSold)) / tokensSold;
            if (remaining < allocatedLeftover) {                           // In case not enough remaining
                allocatedLeftover = remaining;
            }
            leftoverAmountOf[purchaser] = allocatedLeftover;  
            leftoverDistributed[purchaser] = true;                         // leftover distributed
            remaining -= allocatedLeftover;                               
            token.transfer(purchaser, allocatedLeftover);                  // Finally transfer the leftover tokens
            LeftoverTokenDistributed(purchaser, allocatedLeftover);        // signal the event for communication
        }
        if (!hasLeftoverTokens() || remaining < MIN_FTX_PURCHASE) {
            token.transfer(owner, remaining);                              // Balance everything out
            LeftoverTokenDistributed(owner,remaining);                     // signal the event for communication
        }
    }

    /*
        Corwdsale Dapp calls these helper functions.
    */
    function isSaleActive() public view returns (bool) {
        return (isPrivatePresale() || (!privateSoftCapReached && isPublicPresale()) || isCrowdsale()) && !hasEnded();                       // return true if sales is on
    }

    /*
        For the convenience of crowdsale interface to find current discount tier.
    */
    function getTier() public view returns (uint256) {
        uint256 tier = 1;                                                           // Assume presale top tier discount
        if (now >= privateStartDate) {      
            if (isPrivatePresale() || isPublicPresale()) {
                if (getSoftCapReached()) {
                    tier = 2;                                                       // tier 2 discount
                }
            } else {
                for (uint di = 0; di < tokenDiscount.length; di++) {
                    TokenDiscount storage ts = tokenDiscount[di];
                    if (ts.tokensSold < ts.tokensAvail && tier == 1) {
                        tier = di + 3;                                              // 3 means tier 1 for crowdsale
                    }
                }
            }
        }
        return tier;
    }

    /*
        For the convenience of crowdsale interface to present status info.
    */
    function getSoftCapReached() public view returns(bool) {
        return privateSoftCapReached || publicSoftCapReached;
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
        if (now < privateStartDate) {
            return([0,privateStartDate,privateEndDate]);
        } else if (now <= privateEndDate) {
            return([1,privateStartDate,privateEndDate]);
        } else if (now < publicStartDate) {
            if (privateSoftCapReached)
                return([4,startDate,endDate]);
            else    
                return([2,publicStartDate,publicEndDate]);
        } else if (now <= publicEndDate) {
            return([3,publicStartDate,publicEndDate]);
        } else if (now < startDate)
            return([4,startDate,endDate]);
        else if (now <= endDate && !hasEnded())
            return([5,startDate,endDate]);
        else 
            return([6,startDate,endDate]);
    }
}