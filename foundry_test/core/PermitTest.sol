// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

/*  *** CHEAT SHEET ********************************

  Cheat sheet about ethers.js sig generation

  // Follow https://eips.ethereum.org/EIPS/eip-2612

  declare owner: Signer;

  const domain = {
    name: "Mangrove",
    version: "1",
    chainId: 31337, // hardhat chainid
    verifyingContract: mgvAddress,
  };

  const types = {
    Permit: [
      { name: "base", type: "address" },
      { name: "quote", type: "address" },
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
      { name: "value", type: "uint256" },
      { name: "nonce", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
  };

  const data = {
    base: baseAddress,
    quote: quoteAddress,
    owner: await owner.getAddress(),
    spender: permit.address,
    value: value,
    nonce: 0,
    deadline: deadline,
  };

  owner._signTypedData(domain, types, data);

*/

import "mgv_test/lib/MangroveTest.sol";
import {Vm} from "forge-std/Vm.sol";

contract PermitTest is MangroveTest, TrivialTestMaker {
  using stdStorage for StdStorage;
  using mgvPermitData for mgvPermitData.t;

  AbstractMangrove mgv;
  address base;
  address quote;

  uint bad_owner_key;
  address bad_owner;
  uint good_owner_key;
  address good_owner;
  mgvPermitData.t permit_data;

  function setUp() public {
    TestToken baseT = setupToken("A", "$A");
    TestToken quoteT = setupToken("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    mgv = setupMangrove(baseT, quoteT);

    bool noRevert;
    (noRevert, ) = address(mgv).call{value: 10 ether}("");

    (bad_owner_key, bad_owner) = freshAccount("bad owner");
    (good_owner_key, good_owner) = freshAccount("good owner");

    vm.prank(good_owner);
    quoteT.approve(address(mgv), type(uint).max);

    baseT.mint(address(this), 2 ether);
    quoteT.mint(msg.sender, 2 ether);
    quoteT.mint(good_owner, 2 ether);

    baseT.approve(address(mgv), 1 ether);

    vm.label(msg.sender, "Permit signer");
    vm.label(address(this), "Permit Helper");
    vm.label(base, "$A");
    vm.label(quote, "$B");
    vm.label(address(mgv), "mgv");

    mgv.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0, 0);

    permit_data = mgvPermitData.t({
      outbound_tkn: base,
      inbound_tkn: quote,
      owner: good_owner,
      spender: address(this),
      value: 1 ether,
      nonce: 0,
      deadline: block.timestamp + 1,
      v: 0,
      r: 0,
      s: 0,
      key: good_owner_key,
      domain_separator: mgv.DOMAIN_SEPARATOR(),
      permit_typehash: mgv.PERMIT_TYPEHASH(),
      mgv: mgv
    });
  }

  // do a single snipe on mgv for goodOwner
  function snipe(uint value)
    internal
    returns (
      uint,
      uint,
      uint,
      uint,
      uint
    )
  {
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [uint(1), value, value, 300_000];
    return mgv.snipesFor(base, quote, targets, true, good_owner);
  }

  function test_no_allowance() external {
    vm.expectRevert("mgv/lowAllowance");
    snipe(1 ether);
  }

  function test_wrong_owner() public {
    permit_data.signer(bad_owner_key);
    vm.expectRevert("mgv/permit/invalidSignature");
    permit_data.submit();
  }

  function test_wrong_deadline() public {
    permit_data.deadline = 0;
    vm.expectRevert("mgv/permit/expired");
    permit_data.submit();
  }

  function test_late_nonce() public {
    permit_data.nonce = 1;
    vm.expectRevert("mgv/permit/invalidSignature");
    permit_data.submit();
  }

  function test_early_nonce() public {
    stdstore
      .target(address(mgv))
      .sig(mgv.nonces.selector)
      .with_key(good_owner)
      .checked_write(1);

    vm.expectRevert("mgv/permit/invalidSignature");
    permit_data.submit();
  }

  function test_wrong_outbound() public {
    permit_data.outbound_tkn = address(1);
    permit_data.submit();
    assertEq(
      mgv.allowances(base, quote, good_owner, address(this)),
      0,
      "Allowance should be 0"
    );
  }

  function test_wrong_inbound() public {
    permit_data.inbound_tkn = address(1);
    permit_data.submit();
    assertEq(
      mgv.allowances(base, quote, good_owner, address(this)),
      0,
      "Allowance should be 0"
    );
  }

  function test_wrong_spender() public {
    permit_data.spender = address(1);
    permit_data.submit();
    assertEq(
      mgv.allowances(base, quote, good_owner, address(this)),
      0,
      "Allowance should be 0"
    );
  }

  function test_good_permit(uint value) public {
    permit_data.value = value;
    permit_data.submit();

    assertEq(
      mgv.allowances(base, quote, good_owner, address(this)),
      value,
      "Allowance not set"
    );
  }

  function test_allowance_works() public {
    uint value = 1 ether;
    // set allowance manually
    stdstore
      .target(address(mgv))
      .sig(mgv.allowances.selector)
      .with_key(base)
      .with_key(quote)
      .with_key(good_owner)
      .with_key(address(this))
      .checked_write(value);

    (uint successes, uint takerGot, uint takerGave, , ) = snipe(value / 2);
    assertEq(successes, 1, "Snipe should succeed");
    assertEq(
      takerGot,
      value / 2 > 1 ether ? 1 ether : value / 2,
      "takerGot should be 1 ether"
    );
    assertEq(
      takerGave,
      value / 2 > 1 ether ? 1 ether : value / 2,
      "takerGot should be 1 ether"
    );

    assertEq(
      mgv.allowances(base, quote, good_owner, address(this)),
      value / 2 + (value % 2),
      "Allowance incorrectly decreased"
    );
  }
}

/* Permit utilities */

library mgvPermitData {
  Vm private constant vm =
    Vm(address(uint160(uint(keccak256("hevm cheat code")))));

  struct t {
    address outbound_tkn;
    address inbound_tkn;
    address owner;
    address spender;
    uint value;
    uint nonce;
    uint deadline;
    // used at submit() time
    uint key;
    // may not match above fields
    uint8 v;
    bytes32 r;
    bytes32 s;
    // easier to store here (avoids an extra `mgv` arg to lib fns)
    bytes32 permit_typehash;
    bytes32 domain_separator;
    AbstractMangrove mgv;
  }

  function signer(t storage p, uint key) internal returns (t storage) {
    p.key = key;
    return p;
  }

  function sign(t storage p) internal returns (t storage) {
    bytes32 digest = keccak256(
      abi.encodePacked(
        "\x19\x01",
        p.domain_separator,
        keccak256(
          abi.encode(
            p.permit_typehash,
            p.outbound_tkn,
            p.inbound_tkn,
            p.owner,
            p.spender,
            p.value,
            p.nonce,
            p.deadline
          )
        )
      )
    );

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(p.key, digest);
    p.v = v;
    p.r = r;
    p.s = s;
    return p;
  }

  function submit(t storage p) internal {
    sign(p);
    p.mgv.permit({
      outbound_tkn: p.outbound_tkn,
      inbound_tkn: p.inbound_tkn,
      owner: p.owner,
      spender: p.spender,
      value: p.value,
      deadline: p.deadline,
      v: p.v,
      r: p.r,
      s: p.s
    });
  }
}
