pragma solidity ^0.4.18;

import './math/SafeMath.sol';
import "./FTXToken.sol";
import "./ownership/Ownable.sol";
import "./Pausable.sol";
import "./HasNoTokens.sol";

contract FTXCrowdsale is Ownable, Pausable, HasNoTokens {
    using SafeMath for uint256;

    string public constant NAME = "FintruX Crowdsale";
    string public constant VERSION = "0.3";

    FTXToken token;

    // this multi-sig address will be replaced on production:
    address public constant FINTRUX_WALLET = 0xA2d0B62c3d3cBee17f116828ca895Ac5a115bA4a;

    uint256 public privateStartDate = 1512666000;                                   // Dec 7, 2017 5:00 PM UTC
    uint256 public privateEndDate = 1513875600;                                     // Dec 21, 2017 5:00 PM UTC

    uint256 public publicStartDate = 1515344400;                                   // January 7, 2018 5:00 PM UTC
    uint256 public publicEndDate = 1516554000;                                     // January 21, 2018 5:00 PM UTC

    uint256 public presaleStartDate = 0;
    uint256 public presaleEndDate = 0;

    uint256 public startDate = 1518022800;                                          // Feb 7, 2017 5:00 PM UTC
    uint256 public endDate = 1519837200;                                            // Feb 28, 2017 5:00 PM UTC

    uint256 public softcapDuration = 2 days;                                        // after-soft-cap duration

	struct TokenDiscount {
		uint256 tokensAvail;                                                        // total tokens available at this price
		uint256 tokensSold;                                                         // tokens sold at this price
		uint256 tokenPrice;                                                         // number of tokens per ETH
	}
	TokenDiscount[5] public tokenDiscount;

    uint256 public weiRaised = 0;                                                   // total amount of Ether raised in wei
    uint256 public purchaserCount = 0;                                              // total number of investors purchased FTX
    uint256 private purchaserDistributed = 0;                                       // total number of investors that token has been distributed
    uint256 public tokensSold = 0;                                                  // total number of FTX tokens sold
    uint256 public NumWhitelisted = 0;                                              // total number whitelisted

    /* if the minimum funding goal is not reached, investors may withdraw their funds */
    uint256 public constant MIN_FUNDING_GOAL = 5000 * 10**18;

    uint256 public constant PRESALE_TOKEN_SOFT_CAP = 8250000 * 10**18;              // presale ends 48 hours after soft cap of 8,250,000 FTX is reached
    uint256 public constant PRESALE_RATE = 1650;                                    // presale price is 1 ETH to 1,650 FTX
    uint256 public constant SOFTCAP_RATE = 1575;                                    // presale price becomes 1 ETH to 1,575 FTX after softcap is reached
    uint256 public constant TOKEN_HARD_CAP = 75000000 * 10**18;                     // hardcap is 75% of all tokens
    uint256 public constant MIN_PURCHASE = 10**17;                                  // minimum purchase is 0.1 ETH to make the gas worthwhile
    uint256 public constant MIN_FTX_PURCHASE = 150 * 10**18;

    uint256 public presaleWeiRaised = 0;                                            // amount of Ether raised in presale in wei
    uint256 public presaleTokensSold = 0;                                           // number of FTX tokens sold in presale

    bool public isFinalized = false;                                                // it becomes true when token sale is completed
    bool public enableRefund = false;                                               // it becomes true to allow refund when minimum goal not reached
    //bool public enableReclaim = false;                                              // it becomes true to allow recalim when there are unsold tokens
    bool public softCapReached = false;                                             // it becomes true when softcap is reached
    bool public presaleEnded = false;

    /** Indicates the amount of ETH nin wei each address has invested to this crowdsale */
    mapping (address => uint256) public investedAmountOf;

    /** Indicates the amount of tokens this crowdsale has credited for each investor address */
    mapping (address => uint256) public tokenAmountOf;

    /** Indicates the amount of tokens this crowdsale has credited for each investor address */
    mapping (address => uint256) public reclaimedAmountOf;

    address[] public investors;

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
    event RefundsEnabled();                                                         // event logging for refund enabled when minimum goal not reached
    //event ReclaimsEnabled();                                                        // event logging for reclaim enabled when there are unsold tokens
    event Refunded(address indexed beneficiary, uint256 weiAmount);                 // event logging for each individual refunded amount
    //event Reclaimed(address indexed beneficiary, uint256 weiAmount);              // event logging for each individual reclaimed amount

    /*
        Constructor to initialize everything.
    */
    function FTXCrowdsale (address _token, address _owner) public {
        require(_token != address(0));
        require(_owner != address(0));
        token = FTXToken(_token);
        owner = _owner;

        // presale and crowdsale tokens
        tokenAmountOf[owner] = 75000000 * 10**18;

        // bonus tiers
        tokenDiscount[0] = TokenDiscount(3150000 * 10**18, 0, 1575);                // 5.0% bonus
        tokenDiscount[1] = TokenDiscount(5383000 * 10**18, 0, 1538);                // 2.5% bonus
        tokenDiscount[2] = TokenDiscount(10626000 * 10**18, 0, 1518);               // 1.2% bonus
        tokenDiscount[3] = TokenDiscount(18108000 * 10**18, 0, 1509);               // 0.6% bonus
        tokenDiscount[4] = TokenDiscount(37733000 * 10**18, 0, 1500);               // base price

        presaleStartDate = privateStartDate;
        presaleEndDate = privateEndDate;
    }

    /* for testing */
    function setPrivateDate(uint256 newPrivateStartDate, uint256 newPrivateEndDate) public onlyOwner {
        if (!isFinalized) {
            privateStartDate = newPrivateStartDate;
            privateEndDate = newPrivateEndDate;
        }
    }

    function setPublicDate(uint256 newPublicStartDate, uint256 newPublicEndDate) public onlyOwner {
        if (!isFinalized) {
            publicStartDate = newPublicStartDate;
            publicEndDate = newPublicEndDate;
        }
    }

    /* When necessary, adjust presale start date if not truly finalized */
    function setPresaleStartDate(uint newPresaleStartDate) public onlyOwner {
        if (!isFinalized) {
            presaleStartDate = newPresaleStartDate;
        }
    }

    /* When necessary, adjust presale end date if not truly finalized */
    function setPresaleEndDate(uint newPresaleEndDate) public onlyOwner {
        if (!isFinalized) {
            presaleEndDate = newPresaleEndDate;
        }
    }

    /* When necessary, adjust crodwsale start date if not truly finalized */
    function setStartDate(uint newStartDate) public onlyOwner {
        if (!isFinalized) {
            startDate = newStartDate;
        }
    }

    /* When necessary, adjust crowdsale end date if not truly finalized */
    function setEndDate(uint newEndDate) public onlyOwner {
        if (!isFinalized) {
            endDate = newEndDate;
        }
    }

    /*
        add the ether address to whitelist to enable purchase of token.
    */
    function addToWhitelist(address buyer) public onlyOwner {
        require(buyer != address(0));
        
        if (!isWhitelisted(buyer)) {
            whitelist[buyer] = true;
            NumWhitelisted += 1;
        }
    }
    
    // return true if buyer is whitelisted
    function isWhitelisted(address buyer) public constant returns (bool) {
        return whitelist[buyer];
    }

    /*
        perform presale.
    */
    function purchasePresale() internal {
        uint256 tokens = 0;
        if (!softCapReached) {                                                      // still under soft cap

            if (isPublicPresale() && publicStartDate != presaleStartDate ) {
                // update presale dates
                presaleStartDate = publicStartDate;
                presaleEndDate = publicEndDate;
            }

            tokens = msg.value * PRESALE_RATE;                                      // 1 ETH for 1,100 FTX
            if (presaleTokensSold + tokens >= PRESALE_TOKEN_SOFT_CAP) {             // get less if over softcap
                uint256 availablePresaleTokens = PRESALE_TOKEN_SOFT_CAP - presaleTokensSold;
                uint256 softCapTokens = (msg.value - (availablePresaleTokens / PRESALE_RATE)) * SOFTCAP_RATE;
                tokens = availablePresaleTokens + softCapTokens;
                processSale(tokens, SOFTCAP_RATE);                                  // process presale at 1 ETH to 1,050 FTX
                softCapReached = true;                                              // soft cap has been reached
                presaleEnded = true;
                SoftCapReached();                                                   // signal the event for communication
                presaleEndDate = now + softcapDuration;                             // shorten the presale cycle
            } else {
                processSale(tokens, PRESALE_RATE);                                  // process presale @PRESALE_RATE
            }
        } else {
            tokens = msg.value * SOFTCAP_RATE;                                      // 1 ETH to 1,050 FTX
            processSale(tokens, SOFTCAP_RATE);                                      // process presale at 1 ETH to 1,050 FTX
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
        uint256 refundValue = 0;
        uint256 paidValue = msg.value;

        if (tokensSold + ftx > TOKEN_HARD_CAP) {                                    // if maximum is exceeded
            ftxOver = tokensSold + ftx - TOKEN_HARD_CAP;                            // find overage
            refundValue = ftxOver/ftxRate;                                          // overage ETH to refund
            msg.sender.transfer(refundValue);                                       // refund overage ETH
            Refunded(msg.sender, refundValue);                                      // signal the event for communication
            ftx = ftx - ftxOver;                                                    // adjust tokens purchased
            paidValue = paidValue - refundValue;                                    // adjust Ether paid
        }
        if (tokenAmountOf[msg.sender] == 0) {
            purchaserCount++;                                                       // count new purchasers
            investors.push(msg.sender);
        }
        //token.transfer(msg.sender, ftx);                                            // trasnsfer corresponding tokens
        tokenAmountOf[owner] = tokenAmountOf[owner].sub(ftx);                       // deduct FTX from Fintrux account
        tokenAmountOf[msg.sender] = tokenAmountOf[msg.sender].add(ftx);             // record FTX on purchaser account
        investedAmountOf[msg.sender] = investedAmountOf[msg.sender].add(paidValue); // record ETH paid
        weiRaised += paidValue;                                                     // total ETH raised
        tokensSold += ftx;                                                          // total FTX sold
        TokenPurchase(msg.sender, msg.sender, paidValue, ftx);                      // signal the event for communication
    }

    /*
       default functions to buy tokens.
    */
    function () payable public whenNotPaused {
        purchaseFTX();
    }

    function purchaseFTX() internal {
        require(tokensSold < TOKEN_HARD_CAP);                                       // stop if no more token is allocated for sale
        require(msg.sender != address(0));                                                 // stop if address not valid
        require(tokenAmountOf[owner] > 0);                                          // stop if no more token to sell
        require(msg.value >= MIN_PURCHASE);                                         // stop if the purchase is too small
        require(isWhitelisted(msg.sender));                                         // no purchase unless whitelisted

        if (isPresale() || isPotentialPublicPresale()) {
            purchasePresale();                                                      // do presale
        } else if (isCrowdsale()) {
            purchaseCrowdsale();                                                    // do crowdsale
        } else {
            revert();                                                               // do nothing
        }
    }

    /*
        Check to see if this is presale.
    */
    function isPresale() public constant returns (bool) {
        return !isFinalized && now >= presaleStartDate && now <= presaleEndDate;
    }

    function isPublicPresale() public constant returns (bool) {
        return !isFinalized && now >= publicStartDate && now <= publicEndDate;
    }

    function isPotentialPublicPresale() public constant returns (bool) {
        return !isFinalized && isPublicPresale() && !presaleEnded;
    }

    /*
        Check to see if this is crowdsale.
    */
    function isCrowdsale() public constant returns (bool) {
        return !isFinalized && now >= startDate && now <= endDate;
    }

    /*
        Check to see if the crowdsale end date has passed or if all tokens allocated for sale has been purchased.
    */
    function hasEnded() public constant returns (bool) {
        return now > endDate || !hasUnsoldTokens();
    }

    function hasUnsoldTokens() public constant returns (bool) {
        return TOKEN_HARD_CAP - tokensSold > MIN_FTX_PURCHASE;
    }

    /*
        Determine if the minimum goal has been reached.
    */
    function isMinimumGoalReached() public constant returns (bool) {
        return weiRaised >= MIN_FUNDING_GOAL;
    }

    /*
        Called after crowdsale ends, to do some extra finalization work.
    */
    function finalize() public onlyOwner {
        require(!isFinalized);                                                      // do nothing if finalized
        require(hasEnded());                                                        // crowdsale must have ended
        if (isMinimumGoalReached()) {
            //token.burn();                                                           // burn remaining tokens
            // if (TOKEN_HARD_CAP > tokensSold) {
            //     enableReclaim = true;                                                    // now anyone can redeem their Ether
            //     ReclaimsEnabled();                                                       // signal the event for communication
            // }

            //token.transferOwnership(owner);                                         // transfer ownership of contract
            FINTRUX_WALLET.transfer(this.balance);                                  // transfer to FintruX multisig wallet
            FundsTransferred();                                                     // signal the event for communication
        } else {
            require(!enableRefund);                                                 // only do this once
            enableRefund = true;                                                    // now anyone can redeem their Ether
            RefundsEnabled();                                                       // signal the event for communication
        }
        Finalized();                                                                // signal the event for communication
        isFinalized = true;                                                         // mark as finalized
    }

    /*
        Investor requesting a refund if minimum goal not reached.
    */
    function claimRefund() external {
        refund();
    }

    function refund() internal {
        require(enableRefund);                                                      // cannot refund unless authorized
        uint256 depositedValue = investedAmountOf[msg.sender];                      // ETH to refund
        investedAmountOf[msg.sender] = 0;                                           // assume all refunded
        msg.sender.transfer(depositedValue);                                        // refund all ETH
        Refunded(msg.sender, depositedValue);                                       // signal the event for communication
    }

    // function claimTokens() external {
    //     claimTokensFor(msg.sender);
    // }

    function distributeTokensForAll() public onlyOwner {
        for (uint256 i = 0; i < investors.length; i++) {
            distributeTokensFor(investors[i]);
        }
    }

    function distributeTokensForOne(address investor) public onlyOwner {
        distributeTokensFor(investor);
    }

    function distributeTokensFor(address investor) internal {
        require(isFinalized);
        require(tokenAmountOf[investor] > 0);
        require(isMinimumGoalReached());

        uint256 ftxBonus = 0;

        if (hasUnsoldTokens()) {
            ftxBonus = (tokenAmountOf[investor] * (TOKEN_HARD_CAP - tokensSold)) / tokensSold;
            reclaimedAmountOf[investor] = ftxBonus;  
        }

        uint256 ftxPurchased = tokenAmountOf[investor];
        tokenAmountOf[investor] = 0;
        purchaserDistributed++;                                       

        uint256 remaining = token.balanceOf(address(this));

        uint256 ftxReceived = ftxPurchased + ftxBonus;

        if (remaining < ftxReceived) {
            ftxReceived = remaining;
        }

        token.transfer(investor, ftxReceived); 
    }

    function allTokensDistributed() internal view returns (bool) {
        return purchaserDistributed >= purchaserCount;
    }
    
    function transferTokenOwnership() public onlyOwner {
        require(isFinalized);
        require(allTokensDistributed());

        uint256 remaining = token.balanceOf(address(this));

        if (remaining > 0) {
            token.transfer(owner, remaining);
        }

        token.transferOwnership(owner); 
    }

    /*
        Corwdsale Dapp calls these helper functions.
    */
    function isSaleActive() public constant returns (bool) {
        return (isPresale() || isPotentialPublicPresale() || isCrowdsale()) && !hasEnded();                       // return true if sales is on
    }

    /*
        For the convenience of crowdsale interface to find current discount tier.
    */
    function getTier() public constant returns (uint256) {
        uint256 tier = 1;                                                           // Assume presale top tier discount
        if (now >= presaleStartDate) {
            if (isPresale()) {
                if (softCapReached) {
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

    function getCrowdSaleStatus() public constant returns(uint256[3]) {
        // 0 - presale not started
        // 1 - private presale
        // 2 - private presale ended, public presale not started
        // 3 - presale
        // 4 - presale ended, crowsale not started
        // 5 - crowsale
        // 6 - ended
        if (now < privateStartDate)
            return([0,presaleStartDate,presaleEndDate]);
        else if (now <= presaleEndDate) {
            if (now >= publicStartDate)
                return([3,presaleStartDate,presaleEndDate]);
            else
                return([1,presaleStartDate,presaleEndDate]);
        } else if (now < publicStartDate) {
            if (softCapReached)
                return([4,startDate,endDate]);
            else    
                return([2,publicStartDate,publicEndDate]);
        } else if (now <= publicEndDate) {
            if (softCapReached && now > presaleEndDate)
                return([4,startDate,endDate]);
            else    
                return([3,presaleStartDate,presaleEndDate]);
        } else if (now < startDate)
            return([4,startDate,endDate]);
        else if (now <= endDate && !hasEnded())
            return([5,startDate,endDate]);
        else 
            return([6,startDate,endDate]);
    }
}