// SPDX-License-Identifier:	AGPL-3.0
pragma abicoder v2;
pragma solidity ^0.7.4;

import "./TestToken.sol";
import {SafeMath as S} from "../SafeMath.sol";

contract MoneyMarket {
  // all prices are 1:1
  // interest rate is 0
  // the market has infinite liquidity

  // money market must be admin of all tokens to work
  // use token.addAdmin(address(moneyMarket)) to give it admin power

  uint constant RATIO = 13_000; // basis points
  TestToken[] tokens;
  mapping(TestToken => mapping(address => uint)) borrows;
  mapping(TestToken => mapping(address => uint)) lends;

  constructor(TestToken[] memory _tokens) {
    tokens = _tokens;
  }

  function min(uint a, uint b) internal pure returns (uint) {
    return a < b ? a : b;
  }

  function borrow(TestToken token, uint amount) external returns (bool) {
    uint lent = getLends();
    uint borrowed = getBorrows();
    if (S.div(S.mul(S.add(borrowed, amount), RATIO), 10_000) <= lent) {
      borrows[token][msg.sender] += amount;
      token.mint(address(this), amount); // magic minting
      token.transfer(msg.sender, amount);
      return true;
    } else {
      return false;
    }
  }

  function lend(TestToken token, uint amount) external {
    token.transferFrom(msg.sender, address(this), amount);
    lends[token][msg.sender] += amount;
  }

  function repay(TestToken token, uint _amount) external {
    uint amount = min(borrows[token][msg.sender], _amount);
    token.transferFrom(msg.sender, address(this), amount);
    borrows[token][msg.sender] -= amount;
  }

  function redeem(TestToken token, uint _amount) external {
    uint amount = min(lends[token][msg.sender], _amount);
    token.transfer(msg.sender, amount);
    lends[token][msg.sender] -= amount;
  }

  function getBorrows() public view returns (uint total) {
    for (uint i = 0; i < tokens.length; i++) {
      total += borrows[tokens[i]][msg.sender];
    }
  }

  function getLends() public view returns (uint total) {
    for (uint i = 0; i < tokens.length; i++) {
      total += lends[tokens[i]][msg.sender];
    }
  }
}
