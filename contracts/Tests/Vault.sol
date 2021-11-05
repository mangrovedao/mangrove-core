// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.7.0;
pragma abicoder v2;

import "../AbstractMangrove.sol";
import "hardhat/console.sol";

import "./Toolbox/TestUtils.sol";

import "./Agents/TestToken.sol";

// In these tests, the testing contract is the market maker.
contract Vault_Test {
  receive() external payable {}

  AbstractMangrove mgv;
  TestMaker mkr;
  address base;
  address quote;

  function a_beforeAll() public {
    TestToken baseT = TokenSetup.setup("A", "$A");
    TestToken quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    mgv = MgvSetup.setup(baseT, quoteT);
    mkr = MakerSetup.setup(mgv, base, quote);

    address(mkr).transfer(10 ether);

    mkr.provisionMgv(5 ether);
    bool noRevert;
    (noRevert, ) = address(mgv).call{value: 10 ether}("");

    baseT.mint(address(mkr), 2 ether);
    quoteT.mint(address(this), 2 ether);

    baseT.approve(address(mgv), 1 ether);
    quoteT.approve(address(mgv), 1 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Test Contract");
    Display.register(base, "$A");
    Display.register(quote, "$B");
    Display.register(address(mgv), "mgv");
    Display.register(address(mkr), "maker[$A,$B]");
  }

  function initial_vault_value_test() public {
    TestEvents.eq(
      mgv.vault(),
      address(this),
      "initial vault value should be mgv creator"
    );
  }

  function gov_can_set_vault_test() public {
    mgv.setVault(address(0));
    TestEvents.eq(mgv.vault(), address(0), "gov should be able to set vault");
  }
}
