// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../AbstractMangrove.sol";
import "../MgvLib.sol";
import "hardhat/console.sol";

import "./Toolbox/TestUtils.sol";

import "./Agents/TestToken.sol";
import "./Agents/TestMaker.sol";
import "./Agents/TestMoriartyMaker.sol";
import "./Agents/MakerDeployer.sol";
import "./Agents/TestTaker.sol";

/* *********************************************** */
/* THIS IS NOT A `hardhat test-solidity` TEST FILE */
/* *********************************************** */

/* See test/permit.js, this helper sets up a mgv for the javascript tester of the permit functionality */

contract PermitHelper is IMaker {
  receive() external payable {}

  AbstractMangrove mgv;
  address base;
  address quote;

  function makerExecute(ML.SingleOrder calldata)
    external
    override
    returns (bytes32)
  {
    return "";
  }

  function makerPosthook(ML.SingleOrder calldata, ML.OrderResult calldata)
    external
    override
  {}

  constructor() payable {
    TestToken baseT = TokenSetup.setup("A", "$A");
    TestToken quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    mgv = MgvSetup.setup(baseT, quoteT);

    bool noRevert;
    (noRevert, ) = address(mgv).call{value: 10 ether}("");

    baseT.mint(address(this), 2 ether);
    quoteT.mint(msg.sender, 2 ether);

    baseT.approve(address(mgv), 1 ether);

    Display.register(msg.sender, "Permit signer");
    Display.register(address(this), "Permit Helper");
    Display.register(base, "$A");
    Display.register(quote, "$B");
    Display.register(address(mgv), "mgv");

    mgv.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0, 0);
  }

  function mgvAddress() external view returns (address) {
    return address(mgv);
  }

  function baseAddress() external view returns (address) {
    return base;
  }

  function quoteAddress() external view returns (address) {
    return quote;
  }

  function no_allowance() external {
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [uint(1), 1 ether, 1 ether, 300_000];
    try mgv.snipesFor(base, quote, targets, true, msg.sender) {
      revert("snipesFor without allowance should revert");
    } catch Error(string memory reason) {
      if (keccak256(bytes(reason)) != keccak256("mgv/lowAllowance")) {
        revert("revert when no allowance should be due to no allowance");
      }
    }
  }

  function wrong_permit(
    uint value,
    uint deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    try
      mgv.permit({
        outbound_tkn: base,
        inbound_tkn: quote,
        owner: msg.sender,
        spender: address(this),
        value: value,
        deadline: deadline,
        v: v,
        r: r,
        s: s
      })
    {
      revert("Permit with bad v,r,s should revert");
    } catch Error(string memory reason) {
      if (
        keccak256(bytes(reason)) != keccak256("mgv/permit/invalidSignature")
      ) {
        revert("permit failed, but signature should be deemed invalid");
      }
    }
  }

  function expired_permit(
    uint value,
    uint deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    try
      mgv.permit({
        outbound_tkn: base,
        inbound_tkn: quote,
        owner: msg.sender,
        spender: address(this),
        value: value,
        deadline: deadline,
        v: v,
        r: r,
        s: s
      })
    {
      revert("Permit with expired deadline should revert");
    } catch Error(string memory reason) {
      if (keccak256(bytes(reason)) != keccak256("mgv/permit/expired")) {
        revert("permit failed, but deadline should be deemed expired");
      }
    }
  }

  function good_permit(
    uint value,
    uint deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    mgv.permit(
      base,
      quote,
      msg.sender,
      address(this),
      value,
      deadline,
      v,
      r,
      s
    );

    if (mgv.allowances(base, quote, msg.sender, address(this)) != value) {
      revert("Allowance not set");
    }

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [uint(1), 1 ether, 1 ether, 300_000];
    (uint successes, uint takerGot, uint takerGave) = mgv.snipesFor(
      base,
      quote,
      targets,
      true,
      msg.sender
    );
    if (successes != 0) {
      revert("Snipe should succeed");
    }
    if (takerGot != 1 ether) {
      revert("takerGot should be 1 ether");
    }

    if (takerGave != 1 ether) {
      revert("takerGave should be 1 ether");
    }

    if (
      mgv.allowances(base, quote, msg.sender, address(this)) !=
      (value - 1 ether)
    ) {
      revert("Allowance incorrectly decreased");
    }
  }
}
