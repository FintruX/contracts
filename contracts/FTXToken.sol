pragma solidity ^0.4.18;

import "./StandardToken.sol";
import "./ownership/Ownable.sol";

contract FTXToken is StandardToken, Ownable {

    /* metadata */
    string public constant NAME = "Fincoin";
    string public constant SYMBOL = "FTX";
    string public constant VERSION = "0.8";
    uint8 public constant DECIMALS = 18;

    /* all accounts in wei */
    uint256 public constant INITIAL_SUPPLY = 100000000 * 10**18;
    uint256 public constant FINTRUX_RESERVE_FTX = 10000000 * 10**18;
    uint256 public constant CROSS_RESERVE_FTX = 5000000 * 10**18;
    uint256 public constant TEAM_RESERVE_FTX = 10000000 * 10**18;

    // these three multi-sig addresses will be replaced on production:
    address public constant FINTRUX_RESERVE = 0x70e17532cfdA24839Aa31b66fe97Ac85871a4939;
    address public constant CROSS_RESERVE = 0x9Ed8632e7Ba835f9D7b0019546521A514bEa6576;
    address public constant TEAM_RESERVE = 0xc1831b603914468467FA70B14456c4b8572C18E8;

    // assuming Feb 28, 2018 5:00 PM UTC(1519837200) + 1 year, may change for production; 
    uint256 public constant VESTING_DATE = 1519837200 + 1 years;

    // minimum FTX token to be transferred to make the gas worthwhile (avoid micro transfer), cannot be higher than minimal subscribed amount in crowd sale.
    uint256 public token4Gas = 1*10**18;
    // gas in wei to reimburse must be the lowest minimum 0.6Gwei * 80000 gas limit.
    uint256 public gas4Token = 80000*0.6*10**9;
    // minimum wei required in an account to perform an action (avg gas price 4Gwei * avg gas limit 80000).
    uint256 public minGas4Accts = 80000*4*10**9;

    event Withdraw(address indexed from, address indexed to, uint256 value);
    event GasRebateFailed(address indexed to, uint256 value);

    /**
    * @dev Contructor that gives msg.sender all existing tokens. 
    */
    function FTXToken(address _owner) public {
        require(_owner != address(0));
        totalSupply = INITIAL_SUPPLY;
        balances[_owner] = INITIAL_SUPPLY - FINTRUX_RESERVE_FTX - CROSS_RESERVE_FTX - TEAM_RESERVE_FTX;
        balances[FINTRUX_RESERVE] = FINTRUX_RESERVE_FTX;
        balances[CROSS_RESERVE] = CROSS_RESERVE_FTX;
        balances[TEAM_RESERVE] = TEAM_RESERVE_FTX;
        owner = _owner;
    }

    /**
    * @dev transfer token for a specified address
    * @param _to The address to transfer to.
    * @param _value The amount to be transferred.
    */
    function transfer(address _to, uint256 _value) public returns (bool) {
        require(canTransferTokens());                                               // Team tokens lock 1 year
        require(_value > 0 && _value >= token4Gas);                                 // do nothing if less than allowed minimum but do not fail
        balances[msg.sender] = balances[msg.sender].sub(_value);                    // insufficient token balance would revert here inside safemath
        balances[_to] = balances[_to].add(_value);
        Transfer(msg.sender, _to, _value);
        // Keep a minimum balance of gas in all sender accounts. It would not be executed if the account has enough ETH for next action.
        if (this.balance > gas4Token && msg.sender.balance < minGas4Accts) {
            // reimburse gas in ETH to keep a minimal balance for next transaction, use send instead of transfer thus ignore failed rebate(not enough ether to rebate etc.).
            if (!msg.sender.send(gas4Token)) {
                GasRebateFailed(msg.sender,gas4Token);
            }
        }
        return true;
    }
    
    /* When necessary, adjust minimum FTX to transfer to make the gas worthwhile */
    function setToken4Gas(uint256 newFTXAmount) public onlyOwner {
        require(newFTXAmount > 0);                                                  // Upper bound is not necessary.
        token4Gas = newFTXAmount;
    }

    /* Only when necessary such as gas price change, adjust the gas to be reimbursed on every transfer when sender account below minimum */
    function setGas4Token(uint256 newGasInWei) public onlyOwner {
        require(newGasInWei > 0 && newGasInWei <= 840000*10**9);            // must be less than a reasonable gas value
        gas4Token = newGasInWei;
    }

    /* When necessary, adjust the minimum wei required in an account before an reimibusement of fee is triggerred */
    function setMinGas4Accts(uint256 minBalanceInWei) public onlyOwner {
        require(minBalanceInWei > 0 && minBalanceInWei <= 840000*10**9);    // must be less than a reasonable gas value
        minGas4Accts = minBalanceInWei;
    }

    /* This unnamed function is called whenever the owner send Ether to fund the gas fees and gas reimbursement */
    function() payable public onlyOwner {
    }

    /* Owner withdrawal for excessive gas fees deposited */
    function withdrawToOwner (uint256 weiAmt) public onlyOwner {
        require(weiAmt > 0);                                                // do not allow zero transfer
        msg.sender.transfer(weiAmt);
        Withdraw(this, msg.sender, weiAmt);                                 // signal the event for communication only it is meaningful
    }

    /* below are internal functions */
    /*
        FintruX TEAM can only transfer tokens after vesting date of 1 year.
    */
    function canTransferTokens() internal view returns (bool) {
        if (msg.sender == TEAM_RESERVE) {
            return now >= VESTING_DATE;
        } else {
            return true;
        }
    }

}