// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;
pragma abicoder v2;

import "../AbstractMangrove.sol";
import "hardhat/console.sol";
import "../MgvLib.sol";

import "./Toolbox/TestUtils.sol";

import "./Agents/TestToken.sol";
import "./Agents/TestMonitor.sol";

// In these tests, the testing contract is the market maker.
contract Monitor_Test {

  receive() external payable {}

  AbstractMangrove mgv;
  TestMaker mkr;
  MgvMonitor monitor;
  address base;
  address quote;

  function a_beforeAll() public {
    TestToken baseT = TokenSetup.setup("A", "$A");
    TestToken quoteT = TokenSetup.setup("B", "$B");
    monitor = new MgvMonitor();
    base = address(baseT);
    quote = address(quoteT);
    mgv = MgvSetup.setup(baseT, quoteT);
    mkr = MakerSetup.setup(mgv, base, quote);

    payable(mkr).transfer(10 ether);

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

  function initial_monitor_values_test() public {
    (P.Global.t config, ) = mgv.config(base, quote);
    TestEvents.check(!config.useOracle(), "initial useOracle should be false");
    TestEvents.check(!config.notify(), "initial notify should be false");
  }

  function set_monitor_values_test() public {
    mgv.setMonitor(address(monitor));
    mgv.setUseOracle(true);
    mgv.setNotify(true);
    (P.Global.t config, ) = mgv.config(base, quote);
    TestEvents.eq(config.monitor(), address(monitor), "monitor should be set");
    TestEvents.check(config.useOracle(), "useOracle should be set");
    TestEvents.check(config.notify(), "notify should be set");
  }

  function set_oracle_density_with_useOracle_works_test() public {
    mgv.setMonitor(address(monitor));
    mgv.setUseOracle(true);
    mgv.setDensity(base, quote, 898);
    monitor.setDensity(base, quote, 899);
    (, P.Local.t config) = mgv.config(base, quote);
    TestEvents.eq(config.density(), 899, "density should be set oracle");
  }

  function set_oracle_density_without_useOracle_fails_test() public {
    mgv.setMonitor(address(monitor));
    mgv.setDensity(base, quote, 898);
    monitor.setDensity(base, quote, 899);
    (, P.Local.t config) = mgv.config(base, quote);
    TestEvents.eq(config.density(), 898, "density should be set by mgv");
  }

  function set_oracle_gasprice_with_useOracle_works_test() public {
    mgv.setMonitor(address(monitor));
    mgv.setUseOracle(true);
    mgv.setGasprice(900);
    monitor.setGasprice(901);
    (P.Global.t config, ) = mgv.config(base, quote);
    TestEvents.eq(config.gasprice(), 901, "gasprice should be set by oracle");
  }

  function set_oracle_gasprice_without_useOracle_fails_test() public {
    mgv.setMonitor(address(monitor));
    mgv.setGasprice(900);
    monitor.setGasprice(901);
    (P.Global.t config, ) = mgv.config(base, quote);
    TestEvents.eq(config.gasprice(), 900, "gasprice should be set by mgv");
  }

  function invalid_oracle_address_throws_test() public {
    mgv.setMonitor(address(42));
    mgv.setUseOracle(true);
    try mgv.config(base, quote) {
      TestEvents.fail("Call to invalid oracle address should throw");
    } catch {
      TestEvents.succeed();
    }
  }

  function notify_works_on_success_when_set_test() public {
    mkr.approveMgv(IERC20(base), 1 ether);
    mgv.setMonitor(address(monitor));
    mgv.setNotify(true);
    uint ofrId = mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    P.Offer.t offer = mgv.offers(base, quote, ofrId);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofrId, 0.04 ether, 0.05 ether, 100_000];
    (uint successes, , , , ) = mgv.snipes(base, quote, targets, true);
    TestEvents.check(successes == 1, "snipe should succeed");
    (P.Global.t _global, P.Local.t _local) = mgv.config(base, quote);
    _local = _local.best(1).lock(true);

    ML.SingleOrder memory order = ML.SingleOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      offerId: ofrId,
      offer: offer,
      wants: 0.04 ether,
      gives: 0.04 ether, // wants has been updated to offer price
      offerDetail: mgv.offerDetails(base, quote, ofrId),
      global: _global,
      local: _local
    });

    TestEvents.expectFrom(address(monitor));
    emit L.TradeSuccess(order, address(this));
  }

  function notify_works_on_fail_when_set_test() public {
    mgv.setMonitor(address(monitor));
    mgv.setNotify(true);
    uint ofrId = mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    P.Offer.t offer = mgv.offers(base, quote, ofrId);
    P.OfferDetail.t offerDetail = mgv.offerDetails(base, quote, ofrId);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofrId, 0.04 ether, 0.05 ether, 100_000];
    (uint successes, , , , ) = mgv.snipes(base, quote, targets, true);
    TestEvents.check(successes == 0, "snipe should fail");

    (P.Global.t _global, P.Local.t _local) = mgv.config(base, quote);
    // config sent during maker callback has stale best and, is locked
    _local = _local.best(1).lock(true);

    ML.SingleOrder memory order = ML.SingleOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      offerId: ofrId,
      offer: offer,
      wants: 0.04 ether,
      gives: 0.04 ether, // gives has been updated to offer price
      offerDetail: offerDetail, // gasprice logged will still be as before failure
      global: _global,
      local: _local
    });

    TestEvents.expectFrom(address(monitor));
    emit L.TradeFail(order, address(this));
  }
}
