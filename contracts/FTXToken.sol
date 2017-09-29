pragma solidity ^0.4.13;

import "./StandardToken.sol";
import "./ownership/Ownable.sol";

contract FTXToken is StandardToken, Ownable {

    /* metadata */
    string public constant NAME = "Fincoin";
    string public constant SYMBOL = "ꭍ";
    string public constant VERSION = "0.1";
    uint256 public constant DECIMALS = 18;

    uint256 public constant INITIAL_SUPPLY = 100000000 * 10**18;
    uint256 public constant FINTRUX_RESERVE_FTX = 10000000 * 10**18;
    uint256 public constant BITRUX_RESERVE_FTX = 5000000 * 10**18;
    uint256 public constant TEAM_RESERVE_FTX = 10000000 * 10**18;

    // these three address will be replaced on production:
    address public constant FINTRUX_RESERVE = 0x044F27F79FAa825bb8F56523Bf53B49a5768B852;
    address public constant BITRUX_RESERVE = 0x4BbFBE461b587434F4FA902fAED2A170C28c5cDA;
    address public constant TEAM_RESERVE = 0xDe8AAB537974045860cAfecC5aa0CC7a055aaEc4;

    uint256 public token4Gas = 5;               // this must be big enough to make the reimbursemnet of gas worthwhile. 
    uint256 public gas4Token = 5000;            // this must be big enough to make the reimbursemnet of gas worthwhile. 
    uint256 public minGas4Accts = 10000;        // this must be big enough to make the reimbursemnet of gas worthwhile. 
    uint256 public vestingDate = 1543510800;    // assuming Nov 29, 2018 5:00 PM UTC for now.
    bool public burned = false;
    
    event Withdraw(address indexed from, address indexed to, uint256 value);

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
        require(canTransferTokens());                                                   // Team tokens lock 1 year
        if (_value < token4Gas) {
            revert();                                                                   // do nothing if less than allowed minimum
        }
        if (balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
            balances[msg.sender] = balances[msg.sender].sub(_value);
            balances[_to] = balances[_to].add(_value);
            Transfer(msg.sender, _to, _value);

            // Keep a minimum balance of gas in all accounts.
            if (msg.sender.balance < minGas4Accts) {
                msg.sender.transfer(gas4Token);                                     // reimburse gas fee to keep a minimal balance for next transaction
            }
            if (_to.balance < minGas4Accts) {
                _to.transfer(gas4Token);
            }
            return true;
        } else {
            return false;
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
        vestingDate = now + 1 years;
        burned = true;
    }

    function setToken4Gas(uint newFTXAmount) onlyOwner {
        token4Gas = newFTXAmount;
    }

    function setGas4Token(uint newGasInWei) onlyOwner {
        gas4Token = newGasInWei;
    }

    function setMinGas4Accts(uint minBalanceInWei) onlyOwner {
        minGas4Accts = minBalanceInWei;
    }

    /* owner withdrawal */
    function refundToOwner (uint256 weiAmt) onlyOwner {
        if (!msg.sender.send(weiAmt)) {                                     // Send ether to the owner. It's important
            revert();                                                       // To do this last to avoid recursion attacks
        } else {
            Withdraw(this, msg.sender, weiAmt);                             // signal the event for communication
        }
    }

    /* This unnamed function is called whenever the owner tries to send ether to fund the gas fees  */
    function() payable onlyOwner {
    }
}