// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.7.0;
pragma abicoder v2;

import "../AbstractMangrove.sol";
import "hardhat/console.sol";

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

  function initial_monitor_values_test() public {
    (bytes32 config, ) = mgv.config(base, quote);
    TestEvents.check(
      MP.global_unpack_useOracle(config) == 0,
      "initial useOracle should be false"
    );
    TestEvents.check(
      MP.global_unpack_notify(config) == 0,
      "initial notify should be false"
    );
  }

  function set_monitor_values_test() public {
    mgv.setMonitor(address(monitor));
    mgv.setUseOracle(true);
    mgv.setNotify(true);
    (bytes32 config, ) = mgv.config(base, quote);
    TestEvents.eq(
      MP.global_unpack_monitor(config),
      address(monitor),
      "monitor should be set"
    );
    TestEvents.check(
      MP.global_unpack_useOracle(config) > 0,
      "useOracle should be set"
    );
    TestEvents.check(
      MP.global_unpack_notify(config) > 0,
      "notify should be set"
    );
  }

  function set_oracle_density_with_useOracle_works_test() public {
    mgv.setMonitor(address(monitor));
    mgv.setUseOracle(true);
    mgv.setDensity(base, quote, 898);
    monitor.setDensity(base, quote, 899);
    (, bytes32 config) = mgv.config(base, quote);
    TestEvents.eq(
      MP.local_unpack_density(config),
      899,
      "density should be set oracle"
    );
  }

  function set_oracle_density_without_useOracle_fails_test() public {
    mgv.setMonitor(address(monitor));
    mgv.setDensity(base, quote, 898);
    monitor.setDensity(base, quote, 899);
    (, bytes32 config) = mgv.config(base, quote);
    TestEvents.eq(
      MP.local_unpack_density(config),
      898,
      "density should be set by mgv"
    );
  }

  function set_oracle_gasprice_with_useOracle_works_test() public {
    mgv.setMonitor(address(monitor));
    mgv.setUseOracle(true);
    mgv.setGasprice(900);
    monitor.setGasprice(901);
    (bytes32 config, ) = mgv.config(base, quote);
    TestEvents.eq(
      MP.global_unpack_gasprice(config),
      901,
      "gasprice should be set by oracle"
    );
  }

  function set_oracle_gasprice_without_useOracle_fails_test() public {
    mgv.setMonitor(address(monitor));
    mgv.setGasprice(900);
    monitor.setGasprice(901);
    (bytes32 config, ) = mgv.config(base, quote);
    TestEvents.eq(
      MP.global_unpack_gasprice(config),
      900,
      "gasprice should be set by mgv"
    );
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
    bytes32 offer = mgv.offers(base, quote, ofrId);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofrId, 0.04 ether, 0.05 ether, 100_000];
    (uint successes, , ) = mgv.snipes(base, quote, targets, true);
    TestEvents.check(successes == 1, "snipe should succeed");
    (bytes32 _global, bytes32 _local) = mgv.config(base, quote);
    _local = $$(set_local("_local", [["best", 1], ["lock", 1]]));

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
    bytes32 offer = mgv.offers(base, quote, ofrId);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofrId, 0.04 ether, 0.05 ether, 100_000];
    (uint successes, , ) = mgv.snipes(base, quote, targets, true);
    TestEvents.check(successes == 0, "snipe should fail");

    (bytes32 _global, bytes32 _local) = mgv.config(base, quote);
    // config sent during maker callback has stale best and, is locked
    _local = $$(set_local("_local", [["best", 1], ["lock", 1]]));

    ML.SingleOrder memory order = ML.SingleOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      offerId: ofrId,
      offer: offer,
      wants: 0.04 ether,
      gives: 0.04 ether, // gives has been updated to offer price
      offerDetail: mgv.offerDetails(base, quote, ofrId),
      global: _global,
      local: _local
    });

    TestEvents.expectFrom(address(monitor));
    emit L.TradeFail(order, address(this));
  }
}
