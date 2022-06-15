// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;
import "mgv_test/tools/MangroveTest.sol";

// In these tests, the testing contract is the market maker.
contract Vault_Test is MangroveTest {
  //receive() external payable {}

  AbstractMangrove mgv;

  function setUp() public {
    mgv = setupMangrove();
    // mgv = MgvSetup.setup(baseT, quoteT);
    // mkr = MakerSetup.setup(mgv, base, quote);

    // payable(mkr).transfer(10 ether);

    // mkr.provisionMgv(5 ether);
    // bool noRevert;
    // (noRevert, ) = address(mgv).call{value: 10 ether}("");

    // baseT.mint(address(mkr), 2 ether);
    // quoteT.mint(address(this), 2 ether);

    // baseT.approve(address(mgv), 1 ether);
    // quoteT.approve(address(mgv), 1 ether);

    vm.label(msg.sender, "Test Runner");
    vm.label(address(this), "Test Contract");
  }

  function test_initial_vault_value() public {
    assertEq(
      mgv.vault(),
      address(this),
      "initial vault value should be mgv creator"
    );
  }

  function test_gov_can_set_vault() public {
    mgv.setVault(address(0));
    assertEq(mgv.vault(), address(0), "gov should be able to set vault");
  }
}
