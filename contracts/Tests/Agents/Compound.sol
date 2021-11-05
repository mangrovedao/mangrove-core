// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.7.0;
pragma abicoder v2;

import "hardhat/console.sol";

import "../Toolbox/TestUtils.sol";

import "./TestToken.sol";

contract Compound {
  constructor() {}

  mapping(ERC20BL => mapping(address => uint)) deposits;
  mapping(ERC20BL => TestToken) cTokens;

  //function grant(address to, IERC20 token, uint amount) {
  //deposits[token][to] += amount;
  //c(token).mint(to, amount);
  //}

  function c(ERC20BL token) public returns (TestToken) {
    if (address(cTokens[token]) == address(0)) {
      string memory cName = TestUtils.append("c", token.name());
      string memory cSymbol = TestUtils.append("c", token.symbol());
      cTokens[token] = new TestToken(address(this), cName, cSymbol);
    }

    return cTokens[token];
  }

  function mint(ERC20BL token, uint amount) external {
    token.transferFrom(msg.sender, address(this), amount);
    deposits[token][msg.sender] += amount;
    c(token).mint(msg.sender, amount);
  }

  function redeem(
    address to,
    ERC20BL token,
    uint amount
  ) external {
    c(token).burn(msg.sender, amount);
    token.transfer(to, amount);
  }
}
