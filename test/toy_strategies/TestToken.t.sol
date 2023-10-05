// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "@mgv/test/lib/MangroveTest.sol";

contract TestTokenTest is MangroveTest {
  function setUp() public override {
    super.setUp();
    base.setMintLimit(100 * 10 ** base.decimals());
  }

  function test_mint_once_below_limit_succeeds(uint amount) public {
    vm.assume(amount < 100 * 10 ** base.decimals());
    uint b = base.balanceOf(address(this));
    base.mint(100);
    assertEq(base.balanceOf(address(this)), 100 + b, "mint failed");
  }

  function test_mint_once_above_limit_fails() public {
    uint amount = 101 * 10 ** base.decimals();
    vm.expectRevert("Too much minting required");
    base.mint(amount);
  }

  function test_mint_twice_below_limit_fails() public {
    base.mint(10);
    vm.expectRevert("Too frequent minting required");
    base.mint(10);
  }

  function test_admin_can_burn() public {
    base.mint(10);
    vm.expectRevert("TestToken/adminOnly");
    vm.prank(freshAddress());
    base.burn(address(this), 10);
    assertEq(base.balanceOf(address(this)), 10, "guard failed");

    base.burn(address(this), 10);
    assertEq(base.balanceOf(address(this)), 0, "Burn failed");
  }
}
