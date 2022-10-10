// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import "mgv_test/lib/Test2.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";

import "mgv_src/token_adapters/SumToken.sol";

import {console} from "forge-std/console.sol";

contract SumTokenTest is Test2 {
  SumToken sumToken;
  TestToken tokenA;
  TestToken tokenB;

  function setUp() public {
    tokenA = new TestToken(address(this), "Token A", "A", 12);
    tokenB = new TestToken(address(this), "Token B", "B", 12);

    sumToken = new SumToken(tokenA, tokenB);
  }

  function testFailDifferentDecimalsNotAllowed() public {
    TestToken tokenC = new TestToken(address(this), "Token C", "C", tokenA.decimals() + 1);
    new SumToken(tokenA, tokenC);
    new SumToken(tokenC, tokenA);
  }

  function testSymbolsAreCombined() public {
    assertEq(sumToken.symbol(), "A+B");
  }

  function testTotalSupplyIsSum() public {
    assertEq(sumToken.totalSupply(), 0);
    assertEq(tokenA.totalSupply(), 0);
    assertEq(tokenA.totalSupply(), 0);

    tokenA.mint(address(this), 2);
    assertEq(sumToken.totalSupply(), 2);

    tokenB.mint(address(this), 3);
    assertEq(sumToken.totalSupply(), 5);

    tokenA.burn(address(this), 2);
    assertEq(sumToken.totalSupply(), 3);
  }

  function testTotalSupplyOverflowIsMax() public {
    tokenA.mint(address(this), type(uint).max);
    assertEq(sumToken.totalSupply(), type(uint).max);

    tokenB.mint(address(this), type(uint).max);
    assertEq(sumToken.totalSupply(), type(uint).max);
  }

  function testBalanceOfIsSum() public {
    assertEq(sumToken.balanceOf(address(this)), 0);
    assertEq(tokenA.balanceOf(address(this)), 0);
    assertEq(tokenA.balanceOf(address(this)), 0);

    tokenA.mint(address(this), 2);
    assertEq(sumToken.balanceOf(address(this)), 2);

    tokenB.mint(address(this), 3);
    assertEq(sumToken.balanceOf(address(this)), 5);

    tokenA.burn(address(this), 2);
    assertEq(sumToken.balanceOf(address(this)), 3);
  }

  function testBalanceOfOverflowIsMax() public {
    tokenA.mint(address(this), type(uint).max);
    assertEq(sumToken.balanceOf(address(this)), type(uint).max);

    tokenB.mint(address(this), type(uint).max);
    assertEq(sumToken.balanceOf(address(this)), type(uint).max);
  }
}