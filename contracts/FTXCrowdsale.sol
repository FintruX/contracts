pragma solidity ^0.4.13;

import './math/SafeMath.sol';
import "./FTXToken.sol";
import "./ownership/Ownable.sol";
import "./Pausable.sol";
import "./HasNoTokens.sol";

contract FTXCrowdsale is Ownable, Pausable, HasNoTokens {
    using SafeMath for uint256;

    string public constant NAME = "FintruX Crowdsale";
    string public constant VERSION = "0.1";

    FTXToken token;

    // this multi-sig address will be replaced on production:
    address public constant FINTRUX_WALLET = 0xa92587d1faa9d6b51f5639d0f6a8d035bb0ea739;

/* Uncomment this on deployment to production:
    uint256 public presaleStartDate = 1512666000;                                   // Dec 7, 2017 5:00 PM UTC
    uint256 public presaleEndDate = 1513875600;                                     // Dec 21, 2017 5:00 PM UTC
    uint256 public startDate = 1518022800;                                          // Feb 7, 2017 5:00 PM UTC
    uint256 public endDate = 1519837200;                                            // Feb 28, 2017 5:00 PM UTC
    uint256 public softcapDuration = 2 days;                                        // after-soft-cap duration
*/

    uint256 public presaleStartDate = 1506981600;                                   // Oct 2, 2017 10:00 PM UTC
    uint256 public presaleEndDate = 1508950800;                                     // Oct 25, 2017 5:00 PM UTC
    uint256 public startDate = 1510160400;                                          // Nov 8, 2017 5:00 PM UTC
    uint256 public endDate = 1511974800;                                            // Nov 29, 2017 5:00 PM UTC
    uint256 public softcapDuration = 2 minutes;                                     // after-soft-cap duration

	struct TokenDiscount {
		uint256 tokensAvail;                                                        // total tokens available at this price
		uint256 tokensSold;                                                         // tokens sold at this price
		uint256 tokenPrice;                                                         // number of tokens per ETH
	}
	TokenDiscount[5] public tokenDiscount;

    uint256 public weiRaised = 0;                                                   // total amount of Ether raised in wei
    uint256 public purchaserCount = 0;                                              // total number of investors purchased FTX
    uint256 public tokensSold = 0;                                                  // total number of FTX tokens sold

    /* if the minimum funding goal is not reached, investors may withdraw their funds */
    uint256 public constant MIN_FUNDING_GOAL = 10000 * 10**18;

    uint256 public constant PRESALE_TOKEN_SOFT_CAP = 7700000 * 10**18;              // presale ends 48 hours after soft cap of 7,700,000 FTX is reached
    uint256 public constant PRESALE_RATE = 1100;                                    // presale price is 1 ETH to 1,100 FTX
    uint256 public constant SOFTCAP_RATE = 1050;                                    // presale price becomes 1 ETH to 1,050 FTX after softcap is reached
    uint256 public constant TOKEN_HARD_CAP = 75000000 * 10**18;                     // hardcap is 75% of all tokens
    uint256 public constant MIN_PURCHASE = 10**17;                                  // minimum purchase is 0.1 ETH to make the gas worthwhile

    uint256 public presaleWeiRaised = 0;                                            // amount of Ether raised in presale in wei
    uint256 public presaleTokensSold = 0;                                           // number of FTX tokens sold in presale

    bool public isFinalized = false;                                                // it becomes true when token sale is completed
    bool public enableRefund = false;                                               // it becomes true to allow refund when minimum goal not reached
    bool public softCapReached = false;                                             // it becomes true when softcap is reached

    /** Indicates the amount of ETH nin wei each address has invested to this crowdsale */
    mapping (address => uint256) public investedAmountOf;

    /** Indicates the amount of tokens this crowdsale has credited for each investor address */
    mapping (address => uint256) public tokenAmountOf;

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
    event Refunded(address indexed beneficiary, uint256 weiAmount);                 // event logging for each individual refunded amount

    /*
        Constructor to initialize everything.
    */
    function FTXCrowdsale (address _token, address _owner) {
        require(_token != 0x0);
        require(_owner != 0x0);

        token = FTXToken(_token);
        owner = _owner;

        // presale and crowdsale tokens
        tokenAmountOf[owner] = 75000000 * 10**18;

        // bonus tiers
        tokenDiscount[0] = TokenDiscount(3150000 * 10**18, 0, 1050);                // 5.0% bonus
		tokenDiscount[1] = TokenDiscount(5125000 * 10**18, 0, 1025);                // 2.5% bonus
		tokenDiscount[2] = TokenDiscount(10120000 * 10**18, 0, 1012);               // 1.2% bonus
        tokenDiscount[3] = TokenDiscount(20120000 * 10**18, 0, 1006);               // 0.6% bonus
        tokenDiscount[4] = TokenDiscount(36485000 * 10**18, 0, 1000);               // base price
    }

    /*
        perform presale.
    */
    function purchasePresale() internal {
        uint256 tokens = 0;
        if (!softCapReached) {                                                      // still under soft cap
            tokens = msg.value * PRESALE_RATE;                                      // 1 ETH for 1,100 FTX
            if (presaleTokensSold + tokens >= PRESALE_TOKEN_SOFT_CAP) {             // get less if over softcap
                uint256 availablePresaleTokens = PRESALE_TOKEN_SOFT_CAP - presaleTokensSold;
                uint256 softCapTokens = (msg.value - (availablePresaleTokens / PRESALE_RATE)) * SOFTCAP_RATE;
                tokens = availablePresaleTokens + softCapTokens;
                processSale(tokens, SOFTCAP_RATE);                                  // process presale at 1 ETH to 1,050 FTX
                softCapReached = true;                                              // soft cap has been reached
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
        }
        token.transfer(msg.sender, ftx);                                            // trasnsfer corresponding tokens
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
    function () payable whenNotPaused {
        purchaseFTX();
    }

    function purchaseFTX() internal {
        require(tokensSold < TOKEN_HARD_CAP);                                       // stop if no more token is allocated for sale
        require(msg.sender != 0x0);                                                 // stop if address not valid
        require(tokenAmountOf[owner] > 0);                                          // stop if no more token to sell
        require(msg.value >= MIN_PURCHASE);                                         // stop if the purchase is too small

        if (isPresale()) {
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
        return now > endDate || tokensSold >= TOKEN_HARD_CAP;
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
            token.burn();                                                           // burn remaining tokens
            token.transferOwnership(owner);                                         // transfer ownership of contract
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

    /*
        Corwdsale Dapp calls these helper functions.
    */
    function isSaleActive() public constant returns (bool) {
        return (isPresale() || isCrowdsale()) && !hasEnded();                       // return true if sales is on
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
}