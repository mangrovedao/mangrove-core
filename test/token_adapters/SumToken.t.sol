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

  function testDecimalsAreSameAsConstituents() public {
    assertEq(sumToken.decimals(), tokenA.decimals());
    assertEq(sumToken.decimals(), tokenB.decimals());
  }

  function testSymbolsAreCombined() public {
    assertEq(sumToken.symbol(), "A+B");
  }

  function testTotalSupplyIsSum() public {
    assertEq(sumToken.totalSupply(), 0);
    assertEq(tokenA.totalSupply(), 0);
    assertEq(tokenB.totalSupply(), 0);

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
    assertEq(tokenB.balanceOf(address(this)), 0);

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

  function testFailTransferWithoutApprovalOfSumToken() public {
    tokenA.mint(address(this), 3);
    tokenB.mint(address(this), 3);

    address other = freshAddress("other");

    sumToken.transfer(other, 3);
  }

  function testTransferWithAApprovalOfSumToken() public {
    tokenA.approve(address(sumToken), type(uint).max);
    tokenA.mint(address(this), 3);

    address other = freshAddress("other");

    sumToken.transfer(other, 3);

    assertEq(sumToken.balanceOf(address(this)), 0);
    assertEq(tokenA.balanceOf(address(this)), 0);
    assertEq(tokenB.balanceOf(address(this)), 0);

    assertEq(sumToken.balanceOf(other), 3);
    assertEq(tokenA.balanceOf(other), 3);
    assertEq(tokenB.balanceOf(other), 0);
  }

  function testTransferWithBApprovalOfSumToken() public {
    tokenB.approve(address(sumToken), type(uint).max);
    tokenB.mint(address(this), 3);

    address other = freshAddress("other");

    sumToken.transfer(other, 3);

    assertEq(sumToken.balanceOf(address(this)), 0);
    assertEq(tokenA.balanceOf(address(this)), 0);
    assertEq(tokenB.balanceOf(address(this)), 0);

    assertEq(sumToken.balanceOf(other), 3);
    assertEq(tokenA.balanceOf(other), 0);
    assertEq(tokenB.balanceOf(other), 3);
  }

  function testTransferAOverB() public {
    tokenA.approve(address(sumToken), type(uint).max);
    tokenB.approve(address(sumToken), type(uint).max);

    tokenA.mint(address(this), 3);
    tokenB.mint(address(this), 2);

    address other = freshAddress("other");

    sumToken.transfer(other, 4);

    assertEq(sumToken.balanceOf(address(this)), 1);
    assertEq(tokenA.balanceOf(address(this)), 0);
    assertEq(tokenB.balanceOf(address(this)), 1);

    assertEq(sumToken.balanceOf(other), 4);
    assertEq(tokenA.balanceOf(other), 3);
    assertEq(tokenB.balanceOf(other), 1);
  }

  function testApproveIsReflectedInAllowance() public {
    address other = freshAddress("other");

    sumToken.approve(other, 1);

    assertEq(sumToken.allowance(address(this), other), 1);
  }

  function testFailTransferFromWithoutApproval() public {
    address owner = freshAddress("owner");
    address recipient = freshAddress("recipient");

    vm.startPrank(owner);
    tokenA.approve(address(sumToken), type(uint).max);
    vm.stopPrank();

    tokenA.mint(owner, 1);

    sumToken.transferFrom(owner, recipient, 1);
  }

  function testTransferFromWithApproval() public {
    address owner = freshAddress("owner");
    address recipient = freshAddress("recipient");

    vm.startPrank(owner);
    tokenA.approve(address(sumToken), type(uint).max);
    sumToken.approve(address(this), 6);
    vm.stopPrank();

    tokenA.mint(owner, 3);

    sumToken.transferFrom(owner, recipient, 2);

    assertEq(sumToken.allowance(owner, address(this)), 4);
    assertEq(sumToken.balanceOf(owner), 1);
    assertEq(sumToken.balanceOf(recipient), 2);
  }

  function testTransferFromWithInfiniteApproval() public {
    address owner = freshAddress("owner");
    address recipient = freshAddress("recipient");

    vm.startPrank(owner);
    tokenA.approve(address(sumToken), type(uint).max);
    sumToken.approve(address(this), type(uint).max);
    vm.stopPrank();

    tokenA.mint(owner, 1);

    sumToken.transferFrom(owner, recipient, 1);

    assertEq(sumToken.allowance(owner, address(this)), type(uint).max);
  }
}
