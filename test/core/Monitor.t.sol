// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "@mgv/test/lib/MangroveTest.sol";
import "@mgv/src/core/MgvLib.sol";

contract MonitorTest is MangroveTest {
  TestMaker mkr;

  bytes monitor_read_cd;
  address monitor;

  receive() external payable {}

  function setUp() public override {
    super.setUp();

    mkr = setupMaker(olKey, "Maker[$(A),$(B)]");

    monitor = freshAddress();
    monitor_read_cd = abi.encodeCall(IMgvMonitor.read, (olKey));

    mkr.provisionMgv(5 ether);

    deal($(base), address(mkr), 2 ether);
  }

  function test_initial_monitor_values() public {
    (Global config,) = mgv.config(olKey);
    assertTrue(!config.useOracle(), "initial useOracle should be false");
    assertTrue(!config.notify(), "initial notify should be false");
  }

  function test_set_monitor_values() public {
    mgv.setMonitor(monitor);
    mgv.setUseOracle(true);
    mgv.setNotify(true);
    expectToMockCall(monitor, monitor_read_cd, abi.encode(0, 0));
    (Global config,) = mgv.config(olKey);
    assertEq(config.monitor(), monitor, "monitor should be set");
    assertTrue(config.useOracle(), "useOracle should be set");
    assertTrue(config.notify(), "notify should be set");
  }

  function test_set_oracle_density_with_useOracle_works() public {
    mgv.setMonitor(monitor);
    mgv.setUseOracle(true);
    mgv.setDensity96X32(olKey, 898 << 32);
    expectToMockCall(monitor, monitor_read_cd, abi.encode(0, DensityLib.from96X32(1 << 32)));
    (, Local config) = mgv.config(olKey);
    assertEq(config.density().to96X32(), 1 << 32, "density should be set oracle");
  }

  function test_set_oracle_density_without_useOracle_fails() public {
    mgv.setMonitor(monitor);
    uint density96X32 = 898 << 32;
    mgv.setDensity96X32(olKey, density96X32);
    (, Local config) = mgv.config(olKey);
    assertEq(config.density().to96X32(), DensityLib.from96X32(density96X32).to96X32(), "density should be set by mgv");
  }

  function test_set_oracle_gasprice_with_useOracle_works() public {
    mgv.setMonitor(monitor);
    mgv.setDensity96X32(olKey, 898 << 32);
    mgv.setUseOracle(true);
    mgv.setGasprice(900);
    expectToMockCall(monitor, monitor_read_cd, abi.encode(1, 0));
    (Global config,) = mgv.config(olKey);
    assertEq(config.gasprice(), 1, "gasprice should be set by oracle");
  }

  function test_set_oracle_gasprice_without_useOracle_fails() public {
    mgv.setMonitor(monitor);
    mgv.setGasprice(900);
    (Global config,) = mgv.config(olKey);
    assertEq(config.gasprice(), 900, "gasprice should be set by mgv");
  }

  function test_invalid_oracle_address_throws() public {
    mgv.setMonitor(monitor);
    mgv.setUseOracle(true);
    vm.expectCall(monitor, monitor_read_cd);
    vm.expectRevert(bytes(""));
    mgv.config(olKey);
  }

  function test_notify_works_on_success_when_set() public {
    deal($(quote), $(this), 10 ether);
    mkr.approveMgv(base, 1 ether);
    mgv.setMonitor(monitor);
    mgv.setNotify(true);
    uint ofrId = mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    Offer offer = mgv.offers(olKey, ofrId);

    Tick tick = offer.tick();

    (Global _global, Local _local) = mgv.config(olKey);
    _local = _local.lock(true);

    MgvLib.SingleOrder memory order = MgvLib.SingleOrder({
      olKey: olKey,
      offerId: ofrId,
      offer: offer,
      takerWants: 0.04 ether,
      takerGives: 0.04 ether, // price is 1
      offerDetail: mgv.offerDetails(olKey, ofrId),
      global: _global,
      local: _local
    });

    expectToMockCall(monitor, abi.encodeCall(IMgvMonitor.notifySuccess, (order, $(this))), bytes(""));

    (uint got,,,) = mgv.marketOrderByTick(olKey, tick, 0.04 ether, true);
    assertTrue(got > 0, "order should succeed");
  }

  function test_notify_works_on_fail_when_set() public {
    deal($(quote), $(this), 10 ether);
    mgv.setMonitor(address(monitor));
    mgv.setNotify(true);
    uint ofrId = mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    Offer offer = mgv.offers(olKey, ofrId);
    OfferDetail offerDetail = mgv.offerDetails(olKey, ofrId);

    Tick tick = offer.tick();

    (Global _global, Local _local) = mgv.config(olKey);
    // config sent during maker callback has stale best and, is locked
    _local = _local.lock(true);

    MgvLib.SingleOrder memory order = MgvLib.SingleOrder({
      olKey: olKey,
      offerId: ofrId,
      offer: offer,
      takerWants: 0.04 ether,
      takerGives: 0.04 ether, // price is 1
      offerDetail: offerDetail, // gasprice logged will still be as before failure
      global: _global,
      local: _local
    });

    expectToMockCall(monitor, abi.encodeCall(IMgvMonitor.notifyFail, (order, $(this))), bytes(""));

    (uint got,,,) = mgv.marketOrderByTick(olKey, tick, 0.04 ether, true);
    assertTrue(got == 0, "order should fail");
  }

  // more a test of Mangrove's fallback implementation than of the Monitor
  function test_monitor_fail_revData_is_correct(uint revLen, bytes1 byteData) public {
    mgv.setMonitor(monitor);
    mgv.setUseOracle(true);
    revLen = bound(revLen, 0, 300);
    bytes memory revData = new bytes(revLen);
    for (uint i = 0; i < revLen; i++) {
      revData[i] = byteData;
    }

    vm.mockCallRevert(monitor, abi.encodeCall(IMgvMonitor.read, (olKey)), revData);

    vm.expectRevert(revData);
    mgv.config(olKey);
  }
}
