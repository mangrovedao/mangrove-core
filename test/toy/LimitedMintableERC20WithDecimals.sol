// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/toy/LimitedMintableERC20WithDecimals.sol";

interface CheatCodes {
  // Gets address for a given private key, (privateKey) => (address)
  function addr(uint) external returns (address);
}

contract LimitedMintableERC20WithDecimalsTest is Test {
  LimitedMintableERC20WithDecimals public token;
  address public admin;
  address public addr1;

  CheatCodes cheats = CheatCodes(HEVM_ADDRESS);

  function setUp() public {
    admin = cheats.addr(1);
    addr1 = cheats.addr(2);
    token = new LimitedMintableERC20WithDecimals(admin, 'Test', 'TST', 18);
  }

  function testMint() public {
    vm.prank(addr1);
    token.mint(addr1, 10_000);
    assertEq(token.balanceOf(addr1), 10_000);

    uint lastBlockTimeStamp = block.timestamp;

    vm.expectRevert("LimitedMintableERC20WithDecimals/lastMintToRecent");
    vm.prank(addr1);
    token.mint(addr1, 10_000);

    vm.prank(admin);
    token.mint(addr1, 10_000);
    assertEq(token.balanceOf(addr1), 20_000);

    vm.warp(lastBlockTimeStamp + 2 days);
    vm.prank(addr1);
    token.mint(addr1, 10_000);
    assertEq(token.balanceOf(addr1), 30_000);
  }
}
