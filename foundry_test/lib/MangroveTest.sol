// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;
import "./Test2.sol";
import {Utilities} from "./Utilities.sol";

import {TestTaker} from "mgv_test/lib/agents/TestTaker.sol";
import {TrivialTestMaker, TestMaker} from "mgv_test/lib/agents/TestMaker.sol";
import {MakerDeployer} from "mgv_test/lib/agents/MakerDeployer.sol";
import {TestMoriartyMaker} from "mgv_test/lib/agents/TestMoriartyMaker.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";

import {AbstractMangrove} from "mgv_src/AbstractMangrove.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {InvertedMangrove} from "mgv_src/InvertedMangrove.sol";
import {IERC20, MgvLib, P, HasMgvEvents, IMaker, ITaker, IMgvMonitor} from "mgv_src/MgvLib.sol";
import {console2 as csl} from "forge-std/console2.sol";

/* *************************************************************** 
   import this file and inherit MangroveTest to get up and running 
   *************************************************************** */

/* This file is useful to:
 * auto-import all testing-useful contracts
 * inherit the standard forge-std/test.sol contract augmented with utilities & mangrove-specific functions
 */

contract MangroveTest is Utilities, Test2, HasMgvEvents {
  // Configure the initial setup.
  // Add fields here to make MangroveTest more configurable.
  struct MangroveTestOptions {
    bool invertedMangrove;
  }

  AbstractMangrove mgv;
  address $mgv;
  address $base;
  address $quote;
  TestToken base;
  TestToken quote;
  address $this;
  MangroveTestOptions options = MangroveTestOptions({invertedMangrove: false});

  /* Defaults:
  - testing contract has
    - 10 ETH funded in mangrove
  - new makers
    - have 10 ETH
  - new takers
    - have 10 ETH
  */
  function setUp() public virtual {
    // shortcuts
    $this = address(this);
    // tokens
    base = new TestToken($this, "A", "$A");
    quote = new TestToken($this, "B", "$B");
    // mangrove deploy
    mgv = setupMangrove(base, quote, options.invertedMangrove);
    // shortcuts
    $base = address(base);
    $quote = address(quote);
    $mgv = address(mgv);
    // start with mgvBalance on mangrove
    mgv.fund{value: 10 ether}();
    // approve mgv
    base.approve($mgv, type(uint).max);
    quote.approve($mgv, type(uint).max);
    // logging
    vm.label(tx.origin, "tx.origin");
    vm.label($this, "Test runner");
    vm.label($base, "$A");
    vm.label($quote, "$B");
    vm.label($mgv, "mgv");
  }

  /* Log offer book */

  event OBState(
    address base,
    address quote,
    uint[] offerIds,
    uint[] wants,
    uint[] gives,
    address[] makerAddr,
    uint[] gasreqs
  );

  /** Two different OB logging methods.
   *
   *  `logOfferBook` will be easy to read in traces
   *
   *  `printOfferBook` will be easy to read in the console.logs section
   */

  /* Log OB with events and hardhat-test-solidity */
  event offers_head(address outbound, address inbound);
  event offers_line(
    uint id,
    uint wants,
    uint gives,
    address maker,
    uint gasreq
  );

  function logOfferBook(
    address $out,
    address $in,
    uint size
  ) internal {
    uint offerId = mgv.best($out, $in);

    // save call results so logs are easier to read
    uint[] memory ids = new uint[](size);
    P.Offer.t[] memory offers = new P.Offer.t[](size);
    P.OfferDetail.t[] memory details = new P.OfferDetail.t[](size);
    uint c = 0;
    while ((offerId != 0) && (c < size)) {
      ids[c] = offerId;
      offers[c] = mgv.offers($out, $in, offerId);
      details[c] = mgv.offerDetails($out, $in, offerId);
      offerId = offers[c].next();
      c++;
    }
    c = 0;
    emit offers_head($out, $in);
    while (c < size) {
      emit offers_line(
        ids[c],
        offers[c].wants(),
        offers[c].gives(),
        details[c].maker(),
        details[c].gasreq()
      );
      c++;
    }
    // emit OBState($out, $in, offerIds, wants, gives, makerAddr, gasreqs);
  }

  /* Log OB with console */
  function printOfferBook(address $out, address $in) internal view {
    uint offerId = mgv.best($out, $in);
    TestToken req_tk = TestToken($in);
    TestToken ofr_tk = TestToken($out);

    console.log(
      append(unicode"┌────┬──Best offer: ", uint2str(offerId), unicode"──────")
    );
    while (offerId != 0) {
      (P.OfferStruct memory ofr, ) = mgv.offerInfo($out, $in, offerId);
      console.log(
        append(
          unicode"│ ",
          append(offerId < 9 ? " " : "", uint2str(offerId)), // breaks on id>99
          unicode" ┆ ",
          toEthUnits(ofr.wants, req_tk.symbol()),
          "  /  ",
          toEthUnits(ofr.gives, ofr_tk.symbol())
        )
      );
      offerId = ofr.next;
    }
    console.log(unicode"└────┴─────────────────────");
  }

  event GasCost(string callname, uint value);

  function execWithCost(
    string memory callname,
    address addr,
    bytes memory data
  ) internal returns (bytes memory) {
    uint g0 = gasleft();
    (bool noRevert, bytes memory retdata) = addr.delegatecall(data);
    require(noRevert, "execWithCost should not revert");
    emit GasCost(callname, g0 - gasleft());
    return retdata;
  }

  struct Balances {
    uint mgvBalanceWei;
    uint mgvBalanceFees;
    uint takerBalanceA;
    uint takerBalanceB;
    uint takerBalanceWei;
    uint[] makersBalanceA;
    uint[] makersBalanceB;
    uint[] makersBalanceWei;
  }
  enum Info {
    makerWants,
    makerGives,
    nextId,
    gasreqreceive_on,
    gasprice,
    gasreq
  }

  function isEmptyOB(address $out, address $in) internal view returns (bool) {
    return mgv.best($out, $in) == 0;
  }

  function getFee(
    address $out,
    address $in,
    uint price
  ) internal view returns (uint) {
    (, P.Local.t local) = mgv.config($out, $in);
    return ((price * local.fee()) / 10000);
  }

  function getProvision(
    address $out,
    address $in,
    uint gasreq
  ) internal view returns (uint) {
    (P.Global.t glo_cfg, P.Local.t loc_cfg) = mgv.config($out, $in);
    return ((gasreq + loc_cfg.offer_gasbase()) *
      uint(glo_cfg.gasprice()) *
      10**9);
  }

  function getProvision(
    address $out,
    address $in,
    uint gasreq,
    uint gasprice
  ) internal view returns (uint) {
    (P.Global.t glo_cfg, P.Local.t loc_cfg) = mgv.config($out, $in);
    uint _gp;
    if (glo_cfg.gasprice() > gasprice) {
      _gp = uint(glo_cfg.gasprice());
    } else {
      _gp = gasprice;
    }
    return ((gasreq + loc_cfg.offer_gasbase()) * _gp * 10**9);
  }

  // Deploy mangrove
  function setupMangrove() public returns (AbstractMangrove) {
    return setupMangrove(false);
  }

  // Deploy mangrove, inverted or not
  function setupMangrove(bool inverted) public returns (AbstractMangrove) {
    if (inverted) {
      return
        new InvertedMangrove({
          governance: $this,
          gasprice: 40,
          gasmax: 1_000_000
        });
    } else {
      return new Mangrove({governance: $this, gasprice: 40, gasmax: 1_000_000});
    }
  }

  // Deploy mangrove with a pair
  function setupMangrove(TestToken outbound_tkn, TestToken inbound_tkn)
    public
    returns (AbstractMangrove)
  {
    return setupMangrove(outbound_tkn, inbound_tkn, false);
  }

  // Deploy mangrove with a pair, inverted or not
  function setupMangrove(
    TestToken outbound_tkn,
    TestToken inbound_tkn,
    bool inverted
  ) public returns (AbstractMangrove _mgv) {
    _mgv = setupMangrove(inverted);
    not0x(address(outbound_tkn));
    not0x(address(outbound_tkn));
    _mgv.activate(address(outbound_tkn), address(inbound_tkn), 0, 0, 20_000);
    _mgv.activate(address(inbound_tkn), address(outbound_tkn), 0, 0, 20_000);
  }

  function setupMaker(
    address $out,
    address $in,
    string memory label
  ) public returns (TestMaker) {
    TestMaker tm = new TestMaker(mgv, IERC20($out), IERC20($in));
    vm.deal(address(tm), 10 ether);
    vm.label(address(tm), label);
    return tm;
  }

  function setupMakerDeployer(address $out, address $in)
    public
    returns (MakerDeployer)
  {
    not0x($mgv);
    return (new MakerDeployer(mgv, $out, $in));
  }

  function setupTaker(
    address $out,
    address $in,
    string memory label
  ) public returns (TestTaker) {
    TestTaker tt = new TestTaker(mgv, IERC20($out), IERC20($in));
    vm.deal(address(tt), 10 ether);
    vm.label(address(tt), label);
    return tt;
  }
}
