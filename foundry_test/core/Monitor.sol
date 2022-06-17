// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";

contract MonitorTest is MangroveTest {
  AbstractMangrove mgv;
  TestMaker mkr;
  address base;
  address quote;

  bytes monitor_read_cd;
  address monitor;

  receive() external payable {}

  function setUp() public {
    TestToken baseT = setupToken("A", "$A");
    TestToken quoteT = setupToken("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    mgv = setupMangrove(baseT, quoteT);
    mkr = setupMaker(mgv, base, quote);

    monitor = freshAddress();
    monitor_read_cd = abi.encodeCall(IMgvMonitor.read, (base, quote));

    payable(mkr).transfer(10 ether);

    mkr.provisionMgv(5 ether);
    bool noRevert;
    (noRevert, ) = address(mgv).call{value: 10 ether}("");

    baseT.mint(address(mkr), 2 ether);
    quoteT.mint(address(this), 2 ether);

    baseT.approve(address(mgv), 1 ether);
    quoteT.approve(address(mgv), 1 ether);

    vm.label(msg.sender, "Test Runner");
    vm.label(address(this), "Test Contract");
    vm.label(base, "$A");
    vm.label(quote, "$B");
    vm.label(address(mgv), "mgv");
    vm.label(address(mkr), "maker[$A,$B]");
  }

  function test_initial_monitor_values() public {
    (P.Global.t config, ) = mgv.config(base, quote);
    assertTrue(!config.useOracle(), "initial useOracle should be false");
    assertTrue(!config.notify(), "initial notify should be false");
  }

  function test_set_monitor_values() public {
    mgv.setMonitor(monitor);
    mgv.setUseOracle(true);
    mgv.setNotify(true);
    expectToMockCall(monitor, monitor_read_cd, abi.encode(0, 0));
    (P.Global.t config, ) = mgv.config(base, quote);
    assertEq(config.monitor(), monitor, "monitor should be set");
    assertTrue(config.useOracle(), "useOracle should be set");
    assertTrue(config.notify(), "notify should be set");
  }

  function test_set_oracle_density_with_useOracle_works() public {
    mgv.setMonitor(monitor);
    mgv.setUseOracle(true);
    mgv.setDensity(base, quote, 898);
    expectToMockCall(monitor, monitor_read_cd, abi.encode(0, 1));
    (, P.Local.t config) = mgv.config(base, quote);
    assertEq(config.density(), 1, "density should be set oracle");
  }

  function test_set_oracle_density_without_useOracle_fails() public {
    mgv.setMonitor(monitor);
    mgv.setDensity(base, quote, 898);
    (, P.Local.t config) = mgv.config(base, quote);
    assertEq(config.density(), 898, "density should be set by mgv");
  }

  function test_set_oracle_gasprice_with_useOracle_works() public {
    mgv.setMonitor(monitor);
    mgv.setDensity(base, quote, 898);
    mgv.setUseOracle(true);
    mgv.setGasprice(900);
    expectToMockCall(monitor, monitor_read_cd, abi.encode(1, 0));
    (P.Global.t config, ) = mgv.config(base, quote);
    assertEq(config.gasprice(), 1, "gasprice should be set by oracle");
  }

  function test_set_oracle_gasprice_without_useOracle_fails() public {
    mgv.setMonitor(monitor);
    mgv.setGasprice(900);
    (P.Global.t config, ) = mgv.config(base, quote);
    assertEq(config.gasprice(), 900, "gasprice should be set by mgv");
  }

  function test_invalid_oracle_address_throws() public {
    mgv.setMonitor(monitor);
    mgv.setUseOracle(true);
    vm.expectCall(monitor, monitor_read_cd);
    try mgv.config(base, quote) {
      fail("Call to invalid oracle address should throw");
    } catch {
      succeed();
    }
  }

  function test_notify_works_on_success_when_set() public {
    mkr.approveMgv(IERC20(base), 1 ether);
    mgv.setMonitor(monitor);
    mgv.setNotify(true);
    uint ofrId = mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    P.Offer.t offer = mgv.offers(base, quote, ofrId);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofrId, 0.04 ether, 0.05 ether, 100_000];

    (P.Global.t _global, P.Local.t _local) = mgv.config(base, quote);
    _local = _local.best(1).lock(true);

    MgvLib.SingleOrder memory order = MgvLib.SingleOrder({
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

    expectToMockCall(
      monitor,
      abi.encodeCall(IMgvMonitor.notifySuccess, (order, address(this))),
      bytes("")
    );

    (uint successes, , , , ) = mgv.snipes(base, quote, targets, true);
    assertTrue(successes == 1, "snipe should succeed");
  }

  function test_notify_works_on_fail_when_set() public {
    mgv.setMonitor(address(monitor));
    mgv.setNotify(true);
    uint ofrId = mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    P.Offer.t offer = mgv.offers(base, quote, ofrId);
    P.OfferDetail.t offerDetail = mgv.offerDetails(base, quote, ofrId);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofrId, 0.04 ether, 0.05 ether, 100_000];

    (P.Global.t _global, P.Local.t _local) = mgv.config(base, quote);
    // config sent during maker callback has stale best and, is locked
    _local = _local.best(1).lock(true);

    MgvLib.SingleOrder memory order = MgvLib.SingleOrder({
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

    expectToMockCall(
      monitor,
      abi.encodeCall(IMgvMonitor.notifyFail, (order, address(this))),
      bytes("")
    );

    (uint successes, , , , ) = mgv.snipes(base, quote, targets, true);
    assertTrue(successes == 0, "snipe should fail");
  }
}
