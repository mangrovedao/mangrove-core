// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;
import "./Test2.sol";
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

// below imports are for the \$( function)
import {AccessControlled} from "mgv_src/strategies/utils/AccessControlled.sol";

/* *************************************************************** 
   import this file and inherit MangroveTest to get up and running 
   *************************************************************** */

/* This file is useful to:
 * auto-import all testing-useful contracts
 * inherit the standard forge-std/test.sol contract augmented with utilities & mangrove-specific functions
 */

contract MangroveTest is Test2, HasMgvEvents {
  using stdStorage for StdStorage;
  // Configure the initial setup.
  // Add fields here to make MangroveTest more configurable.
  struct TokenOptions {
    string name;
    string symbol;
    uint8 decimals;
  }
  struct MangroveTestOptions {
    bool invertedMangrove;
    TokenOptions base;
    TokenOptions quote;
    uint defaultFee;
  }

  AbstractMangrove mgv;
  TestToken base;
  TestToken quote;

  MangroveTestOptions options =
    MangroveTestOptions({
      invertedMangrove: false,
      base: TokenOptions({name: "Base Token", symbol: "$(A)", decimals: 18}),
      quote: TokenOptions({name: "Quote Token", symbol: "$(B)", decimals: 18}),
      defaultFee: 0
    });

  constructor() {
    // generic trace labeling
    vm.label(tx.origin, "tx.origin");
    vm.label($(this), "Test runner");
  }

  /* Defaults:
  - testing contract has
    - 10 ETH funded in mangrove
  - new makers
    - have 100 ETH
  - new takers
    - have 100 ETH
  */
  function setUp() public virtual {
    // tokens
    base = new TestToken(
      $(this),
      options.base.name,
      options.base.symbol,
      options.base.decimals
    );
    quote = new TestToken(
      $(this),
      options.quote.name,
      options.quote.symbol,
      options.quote.decimals
    );
    // mangrove deploy
    mgv = setupMangrove(base, quote, options.invertedMangrove);
    // start with mgvBalance on mangrove
    mgv.fund{value: 10 ether}();
    // approve mgv
    base.approve($(mgv), type(uint).max);
    quote.approve($(mgv), type(uint).max);
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

  /* Log OB with events */
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
      string.concat(
        unicode"┌────┬──Best offer: ",
        uint2str(offerId),
        unicode"──────"
      )
    );
    while (offerId != 0) {
      (P.OfferStruct memory ofr, ) = mgv.offerInfo($out, $in, offerId);
      console.log(
        string.concat(
          unicode"│ ",
          string.concat(offerId < 9 ? " " : "", uint2str(offerId)), // breaks on id>99
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

  function minusFee(
    address $out,
    address $in,
    uint price
  ) internal view returns (uint) {
    (, P.Local.t local) = mgv.config($out, $in);
    return (price * (10_000 - local.fee())) / 10000;
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
  function setupMangrove(bool inverted) public returns (AbstractMangrove _mgv) {
    if (inverted) {
      _mgv = new InvertedMangrove({
        governance: $(this),
        gasprice: 40,
        gasmax: 2_000_000
      });
    } else {
      _mgv = new Mangrove({
        governance: $(this),
        gasprice: 40,
        gasmax: 2_000_000
      });
    }
    vm.label($(_mgv), "Mangrove");
    return _mgv;
  }

  // Deploy mangrove with a pair
  function setupMangrove(IERC20 outbound_tkn, IERC20 inbound_tkn)
    public
    returns (AbstractMangrove)
  {
    return setupMangrove(outbound_tkn, inbound_tkn, false);
  }

  // Deploy mangrove with a pair, inverted or not
  function setupMangrove(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    bool inverted
  ) public returns (AbstractMangrove _mgv) {
    _mgv = setupMangrove(inverted);
    setupMarket(address(outbound_tkn), address(inbound_tkn), _mgv);
  }

  function setupMarket(
    address $a,
    address $b,
    AbstractMangrove _mgv
  ) internal {
    not0x($a);
    not0x($b);
    _mgv.activate($a, $b, options.defaultFee, 0, 20_000);
    _mgv.activate($b, $a, options.defaultFee, 0, 20_000);
    // logging
    vm.label($a, IERC20($a).symbol());
    vm.label($b, IERC20($b).symbol());
  }

  function setupMarket(address $a, address $b) internal {
    setupMarket($a, $b, mgv);
  }

  function setupMarket(IERC20 a, IERC20 b) internal {
    setupMarket(address(a), address(b), mgv);
  }

  function setupMaker(
    address $out,
    address $in,
    string memory label
  ) public returns (TestMaker) {
    TestMaker tm = new TestMaker(mgv, IERC20($out), IERC20($in));
    vm.deal(address(tm), 100 ether);
    vm.label(address(tm), label);
    return tm;
  }

  function setupMakerDeployer(address $out, address $in)
    public
    returns (MakerDeployer)
  {
    not0x($(mgv));
    return (new MakerDeployer(mgv, $out, $in));
  }

  function setupTaker(
    address $out,
    address $in,
    string memory label
  ) public returns (TestTaker) {
    TestTaker tt = new TestTaker(mgv, IERC20($out), IERC20($in));
    vm.deal(address(tt), 100 ether);
    vm.label(address(tt), label);
    return tt;
  }

  /* **** Token conversion */
  /* return underlying amount with correct number of decimals */
  function cash(IERC20 t, uint amount) public returns (uint) {
    savePrank();
    uint decimals = t.decimals();
    restorePrank();
    return amount * 10**decimals;
  }

  /* return underlying amount divided by 10**power */
  function cash(
    IERC20 t,
    uint amount,
    uint power
  ) public returns (uint) {
    return cash(t, amount) / 10**power;
  }

  /* **** Sugar for address conversion */
  function $(AbstractMangrove t) internal pure returns (address payable) {
    return payable(address(t));
  }

  function $(AccessControlled t) internal pure returns (address payable) {
    return payable(address(t));
  }

  function $(TestTaker t) internal pure returns (address payable) {
    return payable(address(t));
  }

  function $(Test t) internal pure returns (address payable) {
    return payable(address(t));
  }

  function $(IERC20 t) internal pure returns (address payable) {
    return payable(address(t));
  }
}
