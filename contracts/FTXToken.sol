pragma solidity ^0.4.13;

import "./StandardToken.sol";
import "./ownership/Ownable.sol";

contract FTXToken is StandardToken, Ownable {

    /* metadata */
    string public constant NAME = "Fincoin";
    string public constant SYMBOL = "ꭍ";
    string public constant VERSION = "0.2";
    uint256 public constant DECIMALS = 18;

    uint256 public constant INITIAL_SUPPLY = 100000000 * 10**18;
    uint256 public constant FINTRUX_RESERVE_FTX = 10000000 * 10**18;
    uint256 public constant BITRUX_RESERVE_FTX = 5000000 * 10**18;
    uint256 public constant TEAM_RESERVE_FTX = 10000000 * 10**18;

    // these three multi-sig addresses will be replaced on production:
    address public constant FINTRUX_RESERVE = 0x044F27F79FAa825bb8F56523Bf53B49a5768B852;
    address public constant BITRUX_RESERVE = 0x4BbFBE461b587434F4FA902fAED2A170C28c5cDA;
    address public constant TEAM_RESERVE = 0xDe8AAB537974045860cAfecC5aa0CC7a055aaEc4;

    uint256 public token4Gas = 5;               // minimum FTX token to be transferred to make the gas worthwhile
    uint256 public gas4Token = 5000;            // gas in wei to reimburse and must be big enough to make it worthwhile
    uint256 public minGas4Accts = 10000;        // this is the minimum wei required in an account to perform an action
    uint256 public vestingDate = 1519837200;    // assuming Feb 28, 2018 5:00 PM UTC; this can change when token sale completes
    bool public burned = false;
    
    event Withdraw(address indexed from, address indexed to, uint256 value);
    event GasRebateFailed(address to, uint256 value);

    /**
    * @dev Contructor that gives msg.sender all existing tokens. 
    */
    function FTXToken(address _owner) {
        totalSupply = INITIAL_SUPPLY;
        
        balances[_owner] = INITIAL_SUPPLY - FINTRUX_RESERVE_FTX - BITRUX_RESERVE_FTX - TEAM_RESERVE_FTX;
        balances[FINTRUX_RESERVE] = FINTRUX_RESERVE_FTX;
        balances[BITRUX_RESERVE] = BITRUX_RESERVE_FTX;
        balances[TEAM_RESERVE] = TEAM_RESERVE_FTX;

        owner = _owner;
    }

    /**
    * @dev transfer token for a specified address
    * @param _to The address to transfer to.
    * @param _value The amount to be transferred.
    */
    function transfer(address _to, uint256 _value) returns (bool) {
        require(canTransferTokens());                                               // Team tokens lock 1 year
        if (_value < token4Gas) {
            revert();                                                               // do nothing if less than allowed minimum
        }
        if (balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
            balances[msg.sender] = balances[msg.sender].sub(_value);
            balances[_to] = balances[_to].add(_value);
            Transfer(msg.sender, _to, _value);

            // Keep a minimum balance of gas in all accounts. It would not be executed if the account has enough ETH for next action.
            if (msg.sender.balance < minGas4Accts) {
                // reimburse gas in ETH to keep a minimal balance for next transaction.
                if (!msg.sender.send(gas4Token)) {
                    GasRebateFailed(msg.sender,gas4Token);
                }
            }
            if (_to.balance < minGas4Accts) {
                // reimburse gas in ETH to keep a minimal balance for next transaction.
                if (_to.send(gas4Token)) {
                    GasRebateFailed(_to,gas4Token);
                }
            }
            return true;
        } else {
            revert();                                                               // Caller may not check "return false;"
        }
    }

    /*
        FintruX TEAM can only transfer tokens after vesting date of 1 year.
    */
    function canTransferTokens() internal returns (bool) {
        if (msg.sender == TEAM_RESERVE) {
            return now > vestingDate;
        } else {
            return true;
        }
    }

    /* 
        burn specified amount of tokens. It must only be executed once or do nothing.
    */
    function burn() onlyOwner {
        require(!burned);
        uint256 remains = balanceOf(msg.sender);
        if (remains > 0) {
            balances[msg.sender] = balances[msg.sender].sub(remains);
            totalSupply = totalSupply.sub(remains);
            Transfer(msg.sender, 0x0, remains);
        }
        vestingDate = now + 1 years;                                        // One year from token sale complete.
        burned = true;
    }

    /* When necessary, adjust minimum FTX to transfer to make the gas worthwhile */
    function setToken4Gas(uint newFTXAmount) onlyOwner {
        token4Gas = newFTXAmount;
    }

    /* When necessary, adjust the gas to be reimbursed on every transfer */
    function setGas4Token(uint newGasInWei) onlyOwner {
        gas4Token = newGasInWei;
    }

    /* When necessary, adjust the minimum wei required in an account before an reimibusement of fee is triggerred */
    function setMinGas4Accts(uint minBalanceInWei) onlyOwner {
        minGas4Accts = minBalanceInWei;
    }

    /* This unnamed function is called whenever the owner send Ether to fund the gas fees and gas reimbursement */
    function() payable onlyOwner {
    }

    /* Owner withdrawal for excessive gas fees deposited */
    function withdrawToOwner (uint256 weiAmt) onlyOwner {
        if (!msg.sender.send(weiAmt)) {                                     // Send ether back to the owner
            revert();
        } else {
            Withdraw(this, msg.sender, weiAmt);                             // signal the event for communication
        }
    }
}