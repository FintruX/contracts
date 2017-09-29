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
    address public wallet;

/* production values: remove this comment on deployment.
    uint256 public presaleStartDate = 1507741200;                                   // Oct 11, 2017 5:00 PM UTC
    uint256 public presaleEndDate = 1508950800;                                     // Oct 25, 2017 5:00 PM UTC
    uint256 public startDate = 1510160400;                                          // Nov 8, 2017 5:00 PM UTC
    uint256 public endDate = 1511974800;                                            // Nov 29, 2017 5:00 PM UTC
    uint256 public softcapDuration = 2 days;                                        // after-soft-cap duration
*/

    uint256 public presaleStartDate = 1507741200;                                   // Sep 11, 2017 5:00 PM UTC
    uint256 public presaleEndDate = 1508950800;                                     // Oct 25, 2017 5:00 PM UTC
    uint256 public startDate = 1510160400;                                          // Nov 8, 2017 5:00 PM UTC
    uint256 public endDate = 1511974800;                                            // Nov 29, 2017 5:00 PM UTC
    uint256 public softcapDuration = 5 minutes;                                     // after-soft-cap duration

	struct TokenDiscount {
		uint256 tokensAvail;                                                        // total tokens available at this price
		uint256 tokensSold;                                                         // tokens sold at this price
		uint256 tokenPrice;                                                         // number of tokens per ETH
	}
	TokenDiscount[5] public tokenDiscount;

    // amount of raised Ether in wei
    uint256 public weiRaised = 0;
    uint256 public purchaserCount = 0;
    uint256 public tokensSold = 0;

    /* if the funding goal is not reached, investors may withdraw their funds */
    uint256 public constant MIN_FUNDING_GOAL = 10000 * 10**18;

    uint256 public constant PRESALE_TOKEN_SOFT_CAP = 7000000 * 10**18;
    uint256 public constant PRESALE_RATE = 700;
    uint256 public constant SOFTCAP_RATE = 650;
    uint256 public constant TOKEN_HARD_CAP = 75000000 * 10**18;
    uint256 public constant MIN_PURCHASE = 10**16;                          // 0.01 ETH

    uint256 public presaleWeiRaised = 0;
    uint256 public presaleTokensSold = 0;

    bool public isFinalized = false;
    bool public enableRefund = false;
    bool public softCapReached = false;

    /** How much ETH each address has invested to this crowdsale */
    mapping (address => uint256) public investedAmountOf;

    /** How much tokens this crowdsale has credited for each investor address */
    mapping (address => uint256) public tokenAmountOf;

    /**
    * event for token purchase logging
    * @param purchaser who paid for the tokens
    * @param beneficiary who got the tokens
    * @param value weis paid for purchase
    * @param amount amount of tokens purchased
    */ 
    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

    event Finalized();
    event SoftCapReached();
    event FundsTransferred();
    event RefundsEnabled();
    event Refunded(address indexed beneficiary, uint256 weiAmount);

    /*
        Constructor to initialize everything.
    */
    function FTXCrowdsale (address _token, address _owner, address _wallet) {
        require(_token != 0x0);
        require(_wallet != 0x0);
        require(_owner != 0x0);

        token = FTXToken(_token);
        wallet = _wallet;
        owner = _owner;

        // crowdsale tokens
        tokenAmountOf[owner] = 75000000 * 10**18;

        // bonus tiers
        tokenDiscount[0] = TokenDiscount(3600000 * 10**18, 0, 600);
		tokenDiscount[1] = TokenDiscount(5500000 * 10**18, 0, 550);
		tokenDiscount[2] = TokenDiscount(10500000 * 10**18, 0, 525);
        tokenDiscount[3] = TokenDiscount(20600000 * 10**18, 0, 515);
        tokenDiscount[4] = TokenDiscount(34800000 * 10**18, 0, 500);
    }

    /*
        perform presale.
    */
    function purchasePresale() internal {
        uint256 tokens = 0;
        if (!softCapReached) {                                                      // still under soft cap
            tokens = msg.value * PRESALE_RATE;                                      // 1 ETH for 700 FTX
            if (presaleTokensSold + tokens >= PRESALE_TOKEN_SOFT_CAP) {             // get less if over softcap
                uint256 availablePresaleTokens = PRESALE_TOKEN_SOFT_CAP - presaleTokensSold;
                uint256 softCapTokens = (msg.value - (availablePresaleTokens / PRESALE_RATE)) * SOFTCAP_RATE;
                tokens = availablePresaleTokens + softCapTokens;
                processSale(tokens, SOFTCAP_RATE);                                  // process presale @SOFTCAP_RATE
                softCapReached = true;                                              // soft cap has been reached
                SoftCapReached();                                                   // signal the event for communication
                presaleEndDate = now + softcapDuration;                                // shorten the presale cycle
            } else {
                processSale(tokens, PRESALE_RATE);                                  // process presale @PRESALE_RATE
            }
        } else {
            tokens = msg.value * SOFTCAP_RATE;                                      // 1 ETH for 650 FTX
            processSale(tokens, SOFTCAP_RATE);                                      // process presale @SOFTCAP_RATE
        }
        presaleTokensSold += tokens;                                                // Presale ETH raised
        presaleWeiRaised += msg.value;                                              // Presale FTX sold
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
        processSale(tokens, currentRate);                                          // process crowdsale
    }

    /*
        process Sale.
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
        require(tokensSold < TOKEN_HARD_CAP);                                       // if maximum has not reached
        require(msg.sender != 0x0);                                                 // valid address required
        require(tokenAmountOf[owner] > 0);                                          // still have valiable tokens
        require(msg.value >= MIN_PURCHASE);                                         // need 0.01 ETH or more

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
        Crowdsale ended pass endDate or if all tokens allocated for sale has been purchased.
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
            wallet.transfer(this.balance);                                          // transfer to multisig wallet
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
        Investor requesting a refund.
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
        Helper functions. Dapp calls these to manage UI.
    */
    function isSaleActive() public constant returns (bool) {
        return (isPresale() || isCrowdsale()) && !hasEnded();                       // return true if sales is on
    }

    function getPresaleEndDate() public constant returns (uint256) {
        return presaleEndDate;                                                      // get new end
    }

    function getEthRaised() public constant returns (uint256) {
        return weiRaised;
    }

    function getPurchaserCount() public constant returns (uint256) {
        return purchaserCount;
    }

    function getTokensSold() public constant returns (uint256) {
        return tokensSold;
    }

    function getStatus() public constant returns (uint256) {
        uint256 statusCd = 0;
        if (now < presaleStartDate) {
            statusCd = 1;                                                           // sales not started
        } else if (isPresale()) {
            statusCd = 2;                                                           // presales has started
        } else if (now > presaleEndDate && now < startDate) {
            statusCd = 3;                                                           // in between presale and crowdsale
        } else if (isCrowdsale()) {
            statusCd = 4;                                                           // crowdsales has started
        } else if (hasEnded()) {
            statusCd = 5;                                                           // crowdsale has ended
        }
        return statusCd;                                                            // unexpected error if zero
    }

    function getTier() public constant returns (uint256) {
        uint256 tier = 1;                                                           // Assume presale top tier discount
        if (now >= presaleStartDate) {
            if (isPresale() && softCapReached) {
                tier = 2;                                                           // tier 2 discount
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