pragma solidity ^0.4.18;


/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 * https://github.com/OpenZeppelin/zeppelin-solidity/
 */
contract Ownable {
  address public owner;                                                     // Operational owner.
  address public masterOwner = 0x5D1EC7558C8D1c40406913ab5dbC0Abf1C96BA42;  // for ownership transfer segregation of duty, hard coded to wallet account

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);


  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender
   * account.
   */
  function Ownable() public {
    owner = msg.sender;
  }


  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }


  /**
   * @dev Allows the current owner to transfer control of the contract to a newOwner.
   * @param newOwner The address to transfer ownership to.
   */
  function transferOwnership(address newOwner) public {
    require(newOwner != address(0));
    require(masterOwner == msg.sender); // only master owner can initiate change to ownershipe
    OwnershipTransferred(owner, newOwner);
    owner = newOwner;
  }

}