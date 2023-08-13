// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {MgvLib, MgvStructs, Tick, DensityLib, LogPriceLib} from "mgv_src/MgvLib.sol";

contract MonitorTest is MangroveTest {
  TestMaker mkr;

  bytes monitor_read_cd;
  address monitor;

  receive() external payable {}

  function setUp() public override {
    super.setUp();

    mkr = setupMaker(ol, "Maker[$(A),$(B)]");

    monitor = freshAddress();
    monitor_read_cd = abi.encodeCall(IMgvMonitor.read, (ol));

    mkr.provisionMgv(5 ether);

    deal($(base), address(mkr), 2 ether);
  }

  function test_initial_monitor_values() public {
    (MgvStructs.GlobalPacked config,) = mgv.config(ol);
    assertTrue(!config.useOracle(), "initial useOracle should be false");
    assertTrue(!config.notify(), "initial notify should be false");
  }

  function test_set_monitor_values() public {
    mgv.setMonitor(monitor);
    mgv.setUseOracle(true);
    mgv.setNotify(true);
    expectToMockCall(monitor, monitor_read_cd, abi.encode(0, 0));
    (MgvStructs.GlobalPacked config,) = mgv.config(ol);
    assertEq(config.monitor(), monitor, "monitor should be set");
    assertTrue(config.useOracle(), "useOracle should be set");
    assertTrue(config.notify(), "notify should be set");
  }

  function test_set_oracle_density_with_useOracle_works() public {
    mgv.setMonitor(monitor);
    mgv.setUseOracle(true);
    mgv.setDensityFixed(ol, 898 << DensityLib.FIXED_FRACTIONAL_BITS);
    expectToMockCall(
      monitor, monitor_read_cd, abi.encode(0, DensityLib.fromFixed(1 << DensityLib.FIXED_FRACTIONAL_BITS))
    );
    (, MgvStructs.LocalPacked config) = mgv.config(ol);
    assertEq(config.density().toFixed(), 1 << DensityLib.FIXED_FRACTIONAL_BITS, "density should be set oracle");
  }

  function test_set_oracle_density_without_useOracle_fails() public {
    mgv.setMonitor(monitor);
    uint density = 898 << DensityLib.FIXED_FRACTIONAL_BITS;
    mgv.setDensityFixed(ol, density);
    (, MgvStructs.LocalPacked config) = mgv.config(ol);
    assertEq(config.density().toFixed(), DensityLib.fromFixed(density).toFixed(), "density should be set by mgv");
  }

  function test_set_oracle_gasprice_with_useOracle_works() public {
    mgv.setMonitor(monitor);
    mgv.setDensityFixed(ol, 898 << DensityLib.FIXED_FRACTIONAL_BITS);
    mgv.setUseOracle(true);
    mgv.setGasprice(900);
    expectToMockCall(monitor, monitor_read_cd, abi.encode(1, 0));
    (MgvStructs.GlobalPacked config,) = mgv.config(ol);
    assertEq(config.gasprice(), 1, "gasprice should be set by oracle");
  }

  function test_set_oracle_gasprice_without_useOracle_fails() public {
    mgv.setMonitor(monitor);
    mgv.setGasprice(900);
    (MgvStructs.GlobalPacked config,) = mgv.config(ol);
    assertEq(config.gasprice(), 900, "gasprice should be set by mgv");
  }

  function test_invalid_oracle_address_throws() public {
    mgv.setMonitor(monitor);
    mgv.setUseOracle(true);
    vm.expectCall(monitor, monitor_read_cd);
    vm.expectRevert(bytes(""));
    mgv.config(ol);
  }

  function test_notify_works_on_success_when_set() public {
    deal($(quote), $(this), 10 ether);
    mkr.approveMgv(base, 1 ether);
    mgv.setMonitor(monitor);
    mgv.setNotify(true);
    uint ofrId = mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    MgvStructs.OfferPacked offer = mgv.offers(ol, ofrId);

    uint[4][] memory targets = wrap_dynamic([ofrId, uint(offer.logPrice()), 0.04 ether, 100_000]);

    (MgvStructs.GlobalPacked _global, MgvStructs.LocalPacked _local) = mgv.config(ol);
    _local = _local.lock(true);

    MgvLib.SingleOrder memory order = MgvLib.SingleOrder({
      ol: ol,
      offerId: ofrId,
      offer: offer,
      wants: 0.04 ether,
      gives: 0.04 ether, // price is 1
      offerDetail: mgv.offerDetails(ol, ofrId),
      global: _global,
      local: _local
    });

    expectToMockCall(monitor, abi.encodeCall(IMgvMonitor.notifySuccess, (order, $(this))), bytes(""));

    (uint successes,,,,) = mgv.snipes(ol, targets, true);
    assertTrue(successes == 1, "snipe should succeed");
  }

  function test_notify_works_on_fail_when_set() public {
    deal($(quote), $(this), 10 ether);
    mgv.setMonitor(address(monitor));
    mgv.setNotify(true);
    uint ofrId = mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    MgvStructs.OfferPacked offer = mgv.offers(ol, ofrId);
    MgvStructs.OfferDetailPacked offerDetail = mgv.offerDetails(ol, ofrId);

    uint[4][] memory targets = wrap_dynamic([ofrId, uint(offer.logPrice()), 0.04 ether, 100_000]);

    (MgvStructs.GlobalPacked _global, MgvStructs.LocalPacked _local) = mgv.config(ol);
    // config sent during maker callback has stale best and, is locked
    _local = _local.lock(true);

    MgvLib.SingleOrder memory order = MgvLib.SingleOrder({
      ol: ol,
      offerId: ofrId,
      offer: offer,
      wants: 0.04 ether,
      gives: 0.04 ether, // price is 1
      offerDetail: offerDetail, // gasprice logged will still be as before failure
      global: _global,
      local: _local
    });

    expectToMockCall(monitor, abi.encodeCall(IMgvMonitor.notifyFail, (order, $(this))), bytes(""));

    (uint successes,,,,) = mgv.snipes(ol, targets, true);
    assertTrue(successes == 0, "snipe should fail");
  }
}
