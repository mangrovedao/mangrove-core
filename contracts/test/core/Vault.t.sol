// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;
import "mgv_test/lib/MangroveTest.sol";

// In these tests, the testing contract is the market maker.
contract VaultTest is MangroveTest {
  function setUp() public override {
    super.setUp();
  }

  function test_initial_vault_value() public {
    assertEq(mgv.vault(), $(this), "initial vault value should be mgv creator");
  }

  function test_gov_can_set_vault() public {
    mgv.setVault(address(0));
    assertEq(mgv.vault(), address(0), "gov should be able to set vault");
  }
}
