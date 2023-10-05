// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

/*  *** JS CHEAT SHEET ******************************

  Cheat sheet about ethers.js sig generation

  // Follow https://eips.ethereum.org/EIPS/eip-2612

  declare owner: Signer;

  const domain = {
    name: "Mangrove",
    version: "1",
    chainId: 31337, // local chainid
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

  owner._signTypedData(domain, types, data);*/

import {MangroveTest} from "@mgv/test/lib/MangroveTest.sol";
import {TrivialTestMaker, TestMaker} from "@mgv/test/lib/agents/TestMaker.sol";
import {Vm} from "@mgv/forge-std/Vm.sol";
import {console2 as console, StdStorage, stdStorage} from "@mgv/forge-std/Test.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import "@mgv/lib/core/TickTreeLib.sol";
import "@mgv/lib/core/TickLib.sol";
import "@mgv/src/core/MgvLib.sol";

contract PermitTest is MangroveTest, TrivialTestMaker {
  using stdStorage for StdStorage;
  using mgvPermitData for mgvPermitData.t;

  uint bad_owner_key;
  address bad_owner;
  uint good_owner_key;
  address good_owner;
  mgvPermitData.t permit_data;

  function setUp() public override {
    super.setUp();

    (bad_owner_key, bad_owner) = freshAccount("bad owner");
    (good_owner_key, good_owner) = freshAccount("good owner");

    vm.prank(good_owner);
    quote.approve($(mgv), type(uint).max);
    deal($(quote), good_owner, 2 ether);

    permit_data = mgvPermitData.t({
      outbound_tkn: $(base),
      inbound_tkn: $(quote),
      owner: good_owner,
      spender: $(this),
      value: 1 ether,
      nonce: 0,
      deadline: block.timestamp + 1,
      key: good_owner_key,
      mgv: mgv,
      permit_typehash: mgv.PERMIT_TYPEHASH(),
      domain_separator: mgv.DOMAIN_SEPARATOR()
    });
  }

  function marketOrderFor(uint value, address who) internal returns (uint, uint, uint, uint) {
    Tick tick = TickLib.tickFromRatio(1, 0);
    return mgv.marketOrderForByTick(olKey, tick, value, true, who);
  }

  function newOfferByVolume(uint amount) internal {
    mgv.newOfferByVolume(olKey, amount, amount, 100_000, 0);
  }

  function test_no_allowance(uint value) external {
    /* You can use 0 from someone who gave you an allowance of 0. */
    value = bound(value, reader.minVolume(olKey, 100_000), type(uint96).max); //can't create an offer below density
    deal($(base), $(this), value);
    deal($(quote), good_owner, value);
    newOfferByVolume(value);
    vm.expectRevert("mgv/lowAllowance");
    marketOrderFor(value, good_owner);
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
    stdstore.target($(mgv)).sig(mgv.nonces.selector).with_key(good_owner).checked_write(1);

    vm.expectRevert("mgv/permit/invalidSignature");
    permit_data.submit();
  }

  function test_wrong_outbound() public {
    permit_data.outbound_tkn = address(1);
    permit_data.submit();
    assertEq(mgv.allowance($(base), $(quote), good_owner, $(this)), 0, "Allowance should be 0");
  }

  function test_wrong_inbound() public {
    permit_data.inbound_tkn = address(1);
    permit_data.submit();
    assertEq(mgv.allowance($(base), $(quote), good_owner, $(this)), 0, "Allowance should be 0");
  }

  function test_wrong_spender() public {
    permit_data.spender = address(1);
    permit_data.submit();
    assertEq(mgv.allowance($(base), $(quote), good_owner, $(this)), 0, "Allowance should be 0");
  }

  function test_good_permit(uint96 value) public {
    permit_data.value = value;
    permit_data.submit();

    assertEq(mgv.allowance($(base), $(quote), good_owner, $(this)), value, "Allowance not set");
  }

  function test_allowance_works() public {
    uint value = 1 ether;
    // set allowance manually
    stdstore.target($(mgv)).sig(mgv.allowance.selector).with_key($(base)).with_key($(quote)).with_key(good_owner)
      .with_key($(this)).checked_write(value);

    deal($(base), $(this), value);
    deal($(quote), good_owner, value);
    newOfferByVolume(value);
    (uint takerGot, uint takerGave,,) = marketOrderFor(value / 2, good_owner);
    assertEq(takerGot, value / 2, "takerGot should be 1 ether");
    assertEq(takerGave, value / 2, "takerGot should be 1 ether");

    assertEq(
      mgv.allowance($(base), $(quote), good_owner, $(this)), value / 2 + (value % 2), "Allowance incorrectly decreased"
    );
  }

  function test_correct_domain_separator() public {
    bytes32 expected = keccak256(
      abi.encode(
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
        keccak256(bytes("Mangrove")),
        keccak256(bytes("1")),
        block.chainid,
        address(mgv)
      )
    );
    assertEq(mgv.DOMAIN_SEPARATOR(), expected, "wrong DOMAIN_SEPARATOR");
  }

  function test_correct_permit_typehash() public {
    bytes32 expected = keccak256(
      "Permit(address outbound_tkn,address inbound_tkn,address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );
    assertEq(mgv.PERMIT_TYPEHASH(), expected, "wrong PERMIT_TYPEHASH");
  }
}

/* Permit utilities */

library mgvPermitData {
  Vm private constant vm = Vm(address(uint160(uint(keccak256("hevm cheat code")))));

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
    // easier to store here (avoids an extra `mgv` arg to lib fns)
    IMangrove mgv;
    // must preread from mangrove since calling mgv
    // just-in-time will trip up `expectRevert`
    // (looking for a fix to this)
    bytes32 permit_typehash;
    bytes32 domain_separator;
  }

  function signer(t storage p, uint key) internal returns (t storage) {
    p.key = key;
    return p;
  }

  function sign(t storage p) internal view returns (uint8 v, bytes32 r, bytes32 s) {
    bytes32 digest = keccak256(
      abi.encodePacked(
        "\x19\x01",
        p.domain_separator,
        keccak256(
          abi.encode(p.permit_typehash, p.outbound_tkn, p.inbound_tkn, p.owner, p.spender, p.value, p.nonce, p.deadline)
        )
      )
    );
    return vm.sign(p.key, digest);
  }

  function submit(t storage p) internal {
    (uint8 v, bytes32 r, bytes32 s) = sign(p);
    p.mgv.permit({
      outbound_tkn: p.outbound_tkn,
      inbound_tkn: p.inbound_tkn,
      owner: p.owner,
      spender: p.spender,
      value: p.value,
      deadline: p.deadline,
      v: v,
      r: r,
      s: s
    });
  }
}
