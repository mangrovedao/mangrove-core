// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {MgvStructs, MAX_TICK, MIN_TICK, LogPriceLib} from "mgv_src/MgvLib.sol";
import {DensityLib} from "mgv_lib/DensityLib.sol";

// In these tests, the testing contract is the market maker.
contract GatekeepingTest is IMaker, MangroveTest {
  receive() external payable {}

  TestTaker tkr;
  TestMaker mkr;
  TestMaker dual_mkr;
  address notAdmin;

  function setUp() public override {
    super.setUp();
    deal($(base), $(this), 10 ether);

    tkr = setupTaker(olKey, "taker[$(A),$(B)]");
    mkr = setupMaker(olKey, "maker[$(A),$(B)]");
    dual_mkr = setupMaker(lo, "maker[$(B),$(A)]");

    mkr.provisionMgv(5 ether);
    dual_mkr.provisionMgv(5 ether);

    deal($(quote), address(tkr), 1 ether);
    deal($(quote), address(mkr), 1 ether);
    deal($(base), address(dual_mkr), 1 ether);

    tkr.approveMgv(quote, 1 ether);

    notAdmin = freshAddress();
  }

  /* # Test Config */

  function test_gov_is_not_sender() public {
    mgv = new Mangrove({governance: notAdmin, gasprice: 0, gasmax: 0});
    assertEq(mgv.governance(), notAdmin, "governance should not be msg.sender");
  }

  function test_gov_cant_be_zero() public {
    vm.expectRevert("mgv/config/gov/not0");
    mgv.setGovernance(address(0));
  }

  function test_gov_can_transfer_rights() public {
    expectFrom($(mgv));
    emit SetGovernance(notAdmin);
    mgv.setGovernance(notAdmin);

    vm.expectRevert("mgv/unauthorized");
    mgv.setFee(olKey, 0);

    expectFrom($(mgv));
    emit SetFee(olKey.hash(), 1);
    vm.prank(notAdmin);
    mgv.setFee(olKey, 1);
  }

  function test_only_gov_can_set_fee() public {
    vm.expectRevert("mgv/unauthorized");
    vm.prank(notAdmin);
    mgv.setFee(olKey, 0);
  }

  function test_only_gov_can_set_density() public {
    vm.expectRevert("mgv/unauthorized");
    vm.prank(notAdmin);
    mgv.setDensityFixed(olKey, 0);
  }

  function test_set_zero_density() public {
    expectFrom($(mgv));
    emit SetDensityFixed(olKey.hash(), 0);
    mgv.setDensityFixed(olKey, 0);
  }

  function test_only_gov_can_kill() public {
    vm.expectRevert("mgv/unauthorized");
    vm.prank(notAdmin);
    mgv.kill();
  }

  function test_killing_updates_config() public {
    (MgvStructs.GlobalPacked global,) = mgv.config(OLKey(address(0), address(0), 0));
    assertTrue(!global.dead(), "mgv should not be dead ");
    expectFrom($(mgv));
    emit Kill();
    mgv.kill();
    (global,) = mgv.config(OLKey(address(0), address(0), 0));
    assertTrue(global.dead(), "mgv should be dead ");
  }

  function test_kill_is_idempotent() public {
    (MgvStructs.GlobalPacked global,) = mgv.config(OLKey(address(0), address(0), 0));
    assertTrue(!global.dead(), "mgv should not be dead ");
    expectFrom($(mgv));
    emit Kill();
    mgv.kill();
    (global,) = mgv.config(OLKey(address(0), address(0), 0));
    assertTrue(global.dead(), "mgv should be dead");
    expectFrom($(mgv));
    emit Kill();
    mgv.kill();
    (global,) = mgv.config(OLKey(address(0), address(0), 0));
    assertTrue(global.dead(), "mgv should still be dead");
  }

  function test_only_gov_can_set_monitor() public {
    vm.expectRevert("mgv/unauthorized");
    vm.prank(notAdmin);
    mgv.setMonitor($(this));
  }

  function test_only_gov_can_set_active() public {
    vm.expectRevert("mgv/unauthorized");
    vm.prank(notAdmin);
    mgv.activate(lo, 0, 100, 0);
  }

  function test_only_gov_can_setGasprice() public {
    vm.expectRevert("mgv/unauthorized");
    vm.prank(notAdmin);
    mgv.setGasprice(0);
  }

  function test_only_gov_can_setGasmax() public {
    vm.expectRevert("mgv/unauthorized");
    vm.prank(notAdmin);
    mgv.setGasmax(0);
  }

  function test_only_gov_can_setGasbase() public {
    vm.expectRevert("mgv/unauthorized");
    vm.prank(notAdmin);
    mgv.setGasbase(olKey, 0);
  }

  function test_empty_mgv_ok() public {
    tkr.marketOrder(0, 0);
  }

  function test_set_fee_ceiling() public {
    vm.expectRevert("mgv/config/fee/8bits");
    mgv.setFee(olKey, uint(type(uint8).max) + 1);
  }

  function test_set_density_ceiling() public {
    vm.expectRevert("mgv/config/density/128bits");
    mgv.setDensityFixed(olKey, uint(type(uint128).max) + 1);
  }

  function test_setGasprice_ceiling() public {
    vm.expectRevert("mgv/config/gasprice/16bits");
    mgv.setGasprice(uint(type(uint16).max) + 1);
  }

  function test_set_zero_gasbase() public {
    mgv.setGasbase(olKey, 0);
  }

  function test_setGasbase_ceiling() public {
    vm.expectRevert("mgv/config/kilo_offer_gasbase/10bits");
    mgv.setGasbase(olKey, 1e3 * (1 << 10));
  }

  function test_setGasmax_ceiling() public {
    vm.expectRevert("mgv/config/gasmax/24bits");
    mgv.setGasmax(uint(type(uint24).max) + 1);
  }

  function test_makerWants_too_big_fails_newOfferByVolume() public {
    vm.expectRevert("mgv/writeOffer/wants/96bits");
    mkr.newOfferByVolume((1 << 96) + 1e28, 1 ether, 10_000, 0);
  }

  function test_makerTick_wider_than_24_bits_fails_newOfferByLogPrice() public {
    vm.expectRevert("mgv/writeOffer/logPrice/outOfRange");
    mkr.newOfferByLogPrice(1 << 23, 1 ether, 10_000, 0);
  }

  function test_retractOffer_wrong_owner_fails() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 10_000, 0);
    vm.expectRevert("mgv/retractOffer/unauthorized");
    mgv.retractOffer(olKey, ofr, false);
  }

  function test_updateOffer_wrong_owner_fails() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    vm.expectRevert("mgv/updateOffer/unauthorized");
    mgv.updateOfferByVolume(olKey, 1 ether, 1 ether, 0, 0, ofr);
  }

  function test_gives_0_rejected() public {
    vm.expectRevert("mgv/writeOffer/gives/tooLow");
    mkr.newOfferByLogPrice(0, 0 ether, 100_000, 0);
  }

  function test_idOverflow_reverts(OLKey memory olKey) public {
    mgv.activate(olKey, 0, 0, 0);

    // To test overflow, we surgically set 'last offer id' in mangrove storage
    // to uint32.max.
    //
    // We use locked(out,in) as a proxy for getting the storage slot of
    // locals[out][in]
    vm.record();
    mgv.locked(olKey);
    (bytes32[] memory reads,) = vm.accesses(address(mgv));
    bytes32 slot = reads[0];
    bytes32 data = vm.load(address(mgv), slot);
    MgvStructs.LocalPacked local = MgvStructs.LocalPacked.wrap(uint(data));
    local = local.last(type(uint32).max);
    vm.store(address(mgv), slot, bytes32(MgvStructs.LocalPacked.unwrap(local)));

    // try new offer now that we set the last id to uint32.max
    vm.expectRevert("mgv/offerIdOverflow");
    mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 0, 0);
  }

  function test_makerGives_wider_than_96_bits_fails_newOfferByVolume() public {
    // formerly:
    // vm.expectRevert("mgv/writeOffer/gives/96bits");
    vm.expectRevert("mgv/priceFromLogPrice/outOfRange");
    mkr.newOfferByVolume(1, 1 << 96, 10_000);
  }

  function test_makerGasreq_wider_than_24_bits_fails_newOfferByVolume() public {
    vm.expectRevert("mgv/writeOffer/gasreq/tooHigh");
    mkr.newOfferByVolume(1, 1, 1 << 24);
  }

  function test_makerGasreq_bigger_than_gasmax_fails_newOfferByVolume() public {
    (MgvStructs.GlobalPacked cfg,) = mgv.config(olKey);
    vm.expectRevert("mgv/writeOffer/gasreq/tooHigh");
    mkr.newOfferByVolume(1, 1, cfg.gasmax() + 1);
  }

  function test_makerGasreq_at_gasmax_succeeds_newOfferByVolume() public {
    (MgvStructs.GlobalPacked cfg,) = mgv.config(olKey);
    // Logging tests
    expectFrom($(mgv));
    emit OfferWrite(
      olKey.hash(),
      address(mkr),
      0, //tick
      1 ether, //quote
      cfg.gasprice(), //gasprice
      cfg.gasmax(), //gasreq
      1 //ofrId
    );
    expectFrom($(mgv));
    emit Debit(address(mkr), reader.getProvision(olKey, cfg.gasmax(), 0));
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, cfg.gasmax());
    assertTrue(mgv.offers(olKey, ofr).isLive(), "Offer should have been inserted");
  }

  function test_makerGasreq_lower_than_density_fails_newOfferByVolume() public {
    mgv.setDensityFixed(olKey, 100 << DensityLib.FIXED_FRACTIONAL_BITS);
    (, MgvStructs.LocalPacked cfg) = mgv.config(olKey);
    uint amount = cfg.density().multiply(1 + cfg.offer_gasbase());
    vm.expectRevert("mgv/writeOffer/density/tooLow");
    mkr.newOfferByVolume(amount - 1, amount - 1, 1);
  }

  function test_makerGasreq_at_density_suceeds() public {
    mgv.setDensityFixed(olKey, 100 << DensityLib.FIXED_FRACTIONAL_BITS);
    (MgvStructs.GlobalPacked glob, MgvStructs.LocalPacked cfg) = mgv.config(olKey);
    uint amount = cfg.density().multiply(1 + cfg.offer_gasbase());
    // Logging tests
    expectFrom($(mgv));
    emit OfferWrite(
      olKey.hash(),
      address(mkr),
      0, //tick
      amount, //quote
      glob.gasprice(), //gasprice
      1, //gasreq
      1 //ofrId
    );
    expectFrom($(mgv));
    emit Debit(address(mkr), reader.getProvision(olKey, 1, 0));
    uint ofr = mkr.newOfferByVolume(amount, amount, 1);
    assertTrue(mgv.offers(olKey, ofr).isLive(), "Offer should have been inserted");
  }

  function test_makerGasprice_wider_than_16_bits_fails_newOfferByVolume() public {
    vm.expectRevert("mgv/writeOffer/gasprice/16bits");
    mkr.newOfferByVolume(1, 1, 1, 1 << 16);
  }

  function test_takerWants_wider_than_160_bits_fails_marketOrder() public {
    vm.expectRevert("mgv/mOrder/takerWants/160bits");
    tkr.marketOrder(1 << 160, 0);
  }

  function test_takerGives_wider_than_160_bits_fails_marketOrder() public {
    vm.expectRevert("mgv/mOrder/takerGives/160bits");
    tkr.marketOrder(0, 1 << 160);
  }

  //FIXME Should add similar tests that make sure volume*price is not too big.
  function test_gives_volume_above_96bits_fails_snipes() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000);
    uint[4][] memory targets = wrap_dynamic([ofr, 0, 1 << 96, type(uint).max]);
    vm.expectRevert("mgv/snipes/volume/96bits");
    mgv.snipes(olKey, targets, true);
  }

  function test_wants_volume_above_96bits_fails_snipes() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000);
    uint[4][] memory targets = wrap_dynamic([ofr, 0, 1 << 96, type(uint).max]);
    vm.expectRevert("mgv/snipes/volume/96bits");
    mgv.snipes(olKey, targets, false);
  }

  function test_initial_allowance_is_zero() public {
    assertEq(mgv.allowances($(base), $(quote), address(tkr), $(this)), 0, "initial allowance should be 0");
  }

  function test_cannot_snipesFor_for_without_allowance() public {
    deal($(base), address(mkr), 1 ether);
    mkr.approveMgv(base, 1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000);
    int logPrice = mgv.offers(olKey, ofr).logPrice();

    vm.expectRevert("mgv/lowAllowance");
    mgv.snipesFor(olKey, wrap_dynamic([ofr, uint(logPrice), 1 ether, 300_000]), true, address(tkr));
  }

  function test_cannot_marketOrderFor_for_without_allowance() public {
    deal($(base), address(mkr), 1 ether);
    mkr.approveMgv(base, 1 ether);
    mkr.newOfferByVolume(1 ether, 1 ether, 100_000);
    vm.expectRevert("mgv/lowAllowance");
    mgv.marketOrderForByVolume(olKey, 1 ether, 1 ether, true, address(tkr));
  }

  function test_can_marketOrderFor_for_with_allowance() public {
    deal($(base), address(mkr), 1 ether);
    mkr.approveMgv(base, 1 ether);
    mkr.newOfferByVolume(1 ether, 1 ether, 100_000);
    tkr.approveSpender($(this), 1.2 ether);
    uint takerGot;
    (takerGot,,,) = mgv.marketOrderForByVolume(olKey, 1 ether, 1 ether, true, address(tkr));
    assertEq(
      mgv.allowances($(base), $(quote), address(tkr), $(this)), 0.2 ether, "allowance should have correctly reduced"
    );
  }

  /* # Internal IMaker setup */

  bytes trade_cb;
  bytes posthook_cb;

  // maker's trade fn for the mgv
  function makerExecute(MgvLib.SingleOrder calldata) external override returns (bytes32 ret) {
    ret; // silence unused function parameter
    bool success;
    if (trade_cb.length > 0) {
      (success,) = $(this).call(trade_cb);
      assertTrue(success, "makerExecute callback must work");
    }
    return "";
  }

  function makerPosthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result) external override {
    bool success;
    order; // silence compiler warning
    if (posthook_cb.length > 0) {
      (success,) = $(this).call(posthook_cb);
      bool tradeResult = (result.mgvData == "mgv/tradeSuccess");
      assertTrue(success == tradeResult, "makerPosthook callback must work");
    }
  }

  /* # Reentrancy */

  /* New Offer failure */

  function newOfferKO() external {
    vm.expectRevert("mgv/reentrancyLocked");
    mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 30_000, 0);
  }

  function test_newOffer_on_reentrancy_fails() public {
    uint ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 100_000, 0);
    trade_cb = abi.encodeCall(this.newOfferKO, ());
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
  }

  /* New Offer success */

  // ! may be called with inverted _base and _quote
  function newOfferOK(OLKey memory olKey) external {
    mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 30_000, 0);
  }

  function test_newOffer_on_reentrancy_succeeds() public {
    uint ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 200_000, 0);
    trade_cb = abi.encodeCall(this.newOfferOK, (lo));
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    assertTrue(mgv.best(lo) == 1, "newOfferByVolume on swapped offerList must work");
  }

  function test_newOffer_on_posthook_succeeds() public {
    uint ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 200_000, 0);
    posthook_cb = abi.encodeCall(this.newOfferOK, (olKey));
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    assertTrue(mgv.best(olKey) == 2, "newOfferByVolume on posthook must work");
  }

  /* Update offer failure */

  function updateOfferKO(uint ofr) external {
    vm.expectRevert("mgv/reentrancyLocked");
    mgv.updateOfferByVolume(olKey, 1 ether, 2 ether, 35_000, 0, ofr);
  }

  function test_updateOffer_on_reentrancy_fails() public {
    uint ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 100_000, 0);
    trade_cb = abi.encodeCall(this.updateOfferKO, (ofr));
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
  }

  /* Update offer success */

  // ! may be called with inverted _base and _quote
  function updateOfferOK(OLKey memory olKey, uint ofr) external {
    mgv.updateOfferByVolume(olKey, 1 ether, 2 ether, 35_000, 0, ofr);
  }

  function test_updateOffer_on_reentrancy_succeeds() public {
    uint other_ofr = mgv.newOfferByVolume(lo, 1 ether, 1 ether, 100_000, 0);

    trade_cb = abi.encodeCall(this.updateOfferOK, (lo, other_ofr));
    uint ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 400_000, 0);
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    assertTrue(mgv.offerDetails(lo, other_ofr).gasreq() == 35_000, "updateOffer on swapped offerList must work");
  }

  function test_updateOffer_on_posthook_succeeds() public {
    uint other_ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 100_000, 0);
    posthook_cb = abi.encodeCall(this.updateOfferOK, (olKey, other_ofr));
    uint ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 300_000, 0);
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    assertTrue(mgv.offerDetails(olKey, other_ofr).gasreq() == 35_000, "updateOffer on posthook must work");
  }

  /* Cancel Offer failure */

  function retractOfferKO(uint id) external {
    vm.expectRevert("mgv/reentrancyLocked");
    mgv.retractOffer(olKey, id, false);
  }

  function test_retractOffer_on_reentrancy_fails() public {
    uint ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 100_000, 0);
    trade_cb = abi.encodeCall(this.retractOfferKO, (ofr));
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
  }

  /* Cancel Offer success */

  function retractOfferOK(OLKey memory olKey, uint id) external {
    uint collected = mgv.retractOffer(olKey, id, false);
    assertEq(collected, 0, "Unexpected collected provision after retract w/o deprovision");
  }

  function test_retractOffer_on_reentrancy_succeeds() public {
    uint other_ofr = mgv.newOfferByVolume(lo, 1 ether, 1 ether, 90_000, 0);
    trade_cb = abi.encodeCall(this.retractOfferOK, (lo, other_ofr));

    uint ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 90_000, 0);
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    assertTrue(mgv.best(lo) == 0, "retractOffer on swapped offerList must work");
  }

  function test_retractOffer_on_posthook_succeeds() public {
    uint other_ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 190_000, 0);
    posthook_cb = abi.encodeCall(this.retractOfferOK, (olKey, other_ofr));

    uint ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 90_000, 0);
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    assertEq(mgv.best(olKey), 0, "retractOffer on posthook must work");
  }

  /* Market Order failure */

  function marketOrderKO() external {
    vm.expectRevert("mgv/reentrancyLocked");
    mgv.marketOrderByVolume(olKey, 0.2 ether, 0.2 ether, true);
  }

  function test_marketOrder_on_reentrancy_fails() public {
    uint ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 100_000, 0);
    trade_cb = abi.encodeCall(this.marketOrderKO, ());
    assertTrue(tkr.take(ofr, 0.1 ether), "take must succeed or test is void");
  }

  /* Market Order Success */

  function marketOrderOK(OLKey memory olKey) external {
    mgv.marketOrderByVolume(olKey, uint(0.5 ether), 0.5 ether, true);
  }

  function test_marketOrder_on_reentrancy_succeeds() public {
    dual_mkr.newOfferByVolume(0.5 ether, 0.5 ether, 30_000, 0);
    uint ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 392_000, 0);
    trade_cb = abi.encodeCall(this.marketOrderOK, (lo));
    assertTrue(tkr.take(ofr, 0.1 ether), "take must succeed or test is void");
    assertTrue(mgv.best(lo) == 0, "2nd market order must have emptied mgv");
  }

  function test_marketOrder_on_posthook_succeeds() public {
    mgv.setGasmax(10_000_000);
    uint ofr = mgv.newOfferByVolume(olKey, 0.5 ether, 0.5 ether, 3500_000, 0);
    mgv.newOfferByVolume(olKey, 0.5 ether, 0.5 ether, 1800_000, 0);
    posthook_cb = abi.encodeCall(this.marketOrderOK, (olKey));
    assertTrue(tkr.take(ofr, 0.6 ether), "take must succeed or test is void");
    assertTrue(mgv.best(olKey) == 0, "2nd market order must have emptied mgv");
  }

  // not gatekeeping! move me.
  function test_no_execution_keeps_ticktree_ok() public {
    mgv.setGasmax(10_000_000);
    uint ofr = mgv.newOfferByVolume(olKey, 0.5 ether, 0.5 ether, 3500_000, 0);
    (uint takerGot, uint takerGave) = tkr.marketOrder(0.5 ether, 0.3 ether);
    // assertGt(takerGot,0,"mo should work");
    // should execute 0 offers due to price mismatch
    assertEq(takerGot, 0, "mo should fail");
    assertTrue(mgv.offers(olKey, ofr).gives() > 0, "offer should still be live");
    (takerGot, takerGave) = tkr.marketOrder(0.5 ether, 0.6 ether);
    assertGt(takerGot, 0, "mo should work");
    assertTrue(mgv.best(olKey) == 0, "2nd market order must have emptied mgv");
  }

  // not gatekeeping! move me.
  function test_only_one_exec_keeps_ticktree_ok() public {
    mgv.setGasmax(10_000_000);
    mgv.newOfferByVolume(olKey, 0.05 ether, 0.05 ether, 3500_000, 0);
    uint ofr2 = mgv.newOfferByVolume(olKey, 0.1 ether, 0.05 ether, 3500_000, 0);
    (uint takerGot, uint takerGave) = tkr.marketOrder(0.1 ether, 0.1 ether);
    assertEq(takerGot, 0.05 ether, "mo should only take ofr");
    assertGt(mgv.offers(olKey, ofr2).gives(), 0, "ofr2 should still be live");
    (takerGot, takerGave) = tkr.marketOrder(0.06 ether, 0.2 ether);
    assertGt(takerGot, 0, "mo should work");
    assertTrue(mgv.best(olKey) == 0, "2nd market order must have emptied mgv");
  }

  // not gatekeeping! move me.
  function test_leaf_is_flushed_case1() public {
    mgv.setGasmax(10_000_000);
    uint id = mgv.newOfferByVolume(olKey, 0.05 ether, 0.05 ether, 3500_000, 0);
    MgvStructs.OfferPacked ofr = mgv.offers(olKey, id);
    // FIXME increasing tick by 2 because tick->price->tick does not round up currently
    // when that is fixed, should replace with tick+1
    Tick nextTick = Tick.wrap(Tick.unwrap(ofr.tick(olKey.tickScale)) + 2);
    uint gives = LogPriceLib.outboundFromInbound(LogPriceLib.fromTick(nextTick, olKey.tickScale), 5 ether);
    uint id2 = mgv.newOfferByVolume(olKey, 5 ether, gives, 3500_000, 0);
    tkr.marketOrder(0.05 ether, 0.05 ether);
    // low-level check
    assertEq(mgv.leafs(olKey, ofr.tick(olKey.tickScale).leafIndex()).getNextOfferId(), id2);
    // high-level check
    assertTrue(mgv.best(olKey) == id2, "2nd market order must have emptied mgv");
  }

  // not gatekeeping! move me.
  // Check that un-caching a nonempty level0 works
  function test_remove_with_new_best_saves_previous_level0() public {
    // make a great offer so its level0 is cached
    uint ofr0 = mgv.newOfferByVolume(olKey, 0.01 ether, 1 ether, 1000000, 0);
    // store some information in another level0 (a worse one)
    uint ofr1 = mgv.newOfferByVolume(olKey, 0.02 ether, 0.05 ether, 1000000, 0);
    Tick tick1 = mgv.offers(olKey, ofr1).tick(olKey.tickScale);
    int index1 = tick1.level0Index();
    // make ofr1 the best offer (ofr1.level0 is now cached, but it also lives in its slot)
    mgv.retractOffer(olKey, ofr0, true);
    // make an offer worse than ofr1
    uint ofr2 = mgv.newOfferByVolume(olKey, 0.05 ether, 0.05 ether, 1000000, 0);
    Tick tick2 = mgv.offers(olKey, ofr2).tick(olKey.tickScale);
    int index2 = tick2.level0Index();

    // ofr2 is now best again. ofr1.level0 is not cached anymore.
    // the question is: is ofr1.level0 in storage updated or not?
    // (if it had originally been empty, the test would always succeed)
    mgv.retractOffer(olKey, ofr1, true);
    assertTrue(index1 != index2, "test should construct ofr1/ofr2 so they are on different level0 nodes");
    assertEq(mgv.level0(olKey, index1), FieldLib.EMPTY, "ofr1's level0 should be empty");
  }

  // FIXME Not Gatekeeping!
  function test_leaf_update_both_first_and_last() public {
    uint ofr0 = mgv.newOfferByVolume(olKey, 0.01 ether, 1 ether, 1000000, 0);
    Tick tick0 = mgv.offers(olKey, ofr0).tick(olKey.tickScale);
    mgv.retractOffer(olKey, ofr0, true);
    assertEq(mgv.leafs(olKey, tick0.leafIndex()), LeafLib.EMPTY, "leaf should be empty");
  }

  /* Snipe failure */

  function snipesKO(uint id) external {
    uint[4][] memory targets =
      wrap_dynamic([id, uint(mgv.offers(olKey, id).logPrice()), type(uint96).max, type(uint48).max]);
    vm.expectRevert("mgv/reentrancyLocked");
    mgv.snipes(olKey, targets, true);
  }

  function test_snipe_on_reentrancy_fails() public {
    uint ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 60_000, 0);
    trade_cb = abi.encodeCall(this.snipesKO, (ofr));
    assertTrue(tkr.take(ofr, 0.1 ether), "take must succeed or test is void");
  }

  /* Snipe success */

  function snipesOK(OLKey memory olKey, uint id) external {
    int logPrice = mgv.offers(olKey, id).logPrice();
    uint[4][] memory targets = wrap_dynamic([id, uint(logPrice), type(uint96).max, type(uint48).max]);
    mgv.snipes(olKey, targets, true);
  }

  function test_snipes_on_reentrancy_succeeds() public {
    uint other_ofr = dual_mkr.newOfferByVolume(1 ether, 1 ether, 30_000);
    trade_cb = abi.encodeCall(this.snipesOK, (lo, other_ofr));

    uint ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 190_000, 0);
    assertTrue(tkr.take(ofr, 0.1 ether), "take must succeed or test is void");
    assertTrue(mgv.best(lo) == 0, "snipe in swapped offerList must work");
  }

  function test_snipes_on_posthook_succeeds() public {
    uint other_ofr = mkr.newOfferByVolume(1 ether, 1 ether, 30_000);
    posthook_cb = abi.encodeCall(this.snipesOK, (olKey, other_ofr));

    uint ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 190_000, 0);
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    assertTrue(mgv.best(olKey) == 0, "snipe in posthook must work");
  }

  function test_newOffer_on_closed_fails() public {
    mgv.kill();
    vm.expectRevert("mgv/dead");
    mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 0, 0);
  }

  /* # Mangrove closed/inactive */

  function test_take_on_closed_fails() public {
    uint ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 0, 0);

    mgv.kill();
    vm.expectRevert("mgv/dead");
    tkr.take(ofr, 1 ether);
  }

  function test_newOffer_on_inactive_fails() public {
    mgv.deactivate(olKey);
    vm.expectRevert("mgv/inactive");
    mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 0, 0);
  }

  function test_receive_on_closed_fails() public {
    mgv.kill();

    (bool success, bytes memory retdata) = $(mgv).call{value: 10 ether}("");
    if (success) {
      fail("receive() should fail on closed market");
    } else {
      string memory r = getReason(retdata);
      assertEq(r, "mgv/dead", "wrong revert reason");
    }
  }

  function test_marketOrder_on_closed_fails() public {
    mgv.kill();
    vm.expectRevert("mgv/dead");
    tkr.marketOrder(1 ether, 1 ether);
  }

  function test_snipe_on_closed_fails() public {
    mgv.kill();
    vm.expectRevert("mgv/dead");
    tkr.take(0, 1 ether);
  }

  function test_withdraw_on_closed_ok() public {
    mgv.kill();
    mgv.withdraw(0.1 ether);
  }

  function test_retractOffer_on_closed_ok() public {
    uint ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 0, 0);
    mgv.kill();
    mgv.retractOffer(olKey, ofr, false);
  }

  function test_updateOffer_on_closed_fails() public {
    uint ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 0, 0);
    mgv.kill();
    vm.expectRevert("mgv/dead");
    mgv.updateOfferByVolume(olKey, 1 ether, 1 ether, 0, 0, ofr);
  }

  function test_activation_emits_events_in_order() public {
    expectFrom($(mgv));
    emit SetActive(lo.hash(), true);
    expectFrom($(mgv));
    emit SetFee(lo.hash(), 7);
    expectFrom($(mgv));
    emit SetDensityFixed(lo.hash(), 0);
    expectFrom($(mgv));
    emit SetGasbase(lo.hash(), 3);
    mgv.activate(lo, 7, 0, 3);
  }

  function test_updateOffer_on_inactive_fails() public {
    uint ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, 0, 0);
    expectFrom($(mgv));
    emit SetActive(olKey.hash(), false);
    mgv.deactivate(olKey);
    vm.expectRevert("mgv/inactive");
    mgv.updateOfferByVolume(olKey, 1 ether, 1 ether, 0, 0, ofr);
  }

  function test_inverted_mangrove_flashloan_fail_if_not_self(address caller) public {
    InvertedMangrove imgv = new InvertedMangrove(address(this),0,0);
    vm.assume(caller != address(imgv));
    MgvLib.SingleOrder memory sor;
    vm.prank(caller);
    vm.expectRevert("mgv/invertedFlashloan/protected");
    imgv.flashloan(sor, address(0));
  }

  function test_mangrove_flashloan_fail_if_not_self(address caller) public {
    vm.assume(caller != address(mgv));
    MgvLib.SingleOrder memory sor;
    vm.prank(caller);
    vm.expectRevert("mgv/flashloan/protected");
    mgv.flashloan(sor, address(0));
  }

  function test_configInfo(OLKey memory olKey, address monitor, uint128 densityFixed) public {
    mgv.activate(olKey, 0, densityFixed, 0);
    mgv.setMonitor(monitor);
    (MgvStructs.GlobalUnpacked memory g, MgvStructs.LocalUnpacked memory l) = mgv.configInfo(olKey);
    assertEq(g.monitor, monitor, "wrong monitor");
    assertEq(l.density.toFixed(), DensityLib.fromFixed(densityFixed).toFixed(), "wrong density");
  }

  function test_nonadmin_cannot_withdrawERC20(address from, address token, uint amount) public {
    vm.assume(from != mgv.governance());
    vm.assume(from != address(mgv));
    vm.expectRevert("mgv/unauthorized");
    vm.prank(from);
    mgv.withdrawERC20(token, amount);
  }

  function test_admin_can_withdrawERC20(uint amount) public {
    TestToken token = new TestToken(address(this),"Withdrawable","WDBL",18);
    deal(address(token), address(mgv), amount);
    mgv.withdrawERC20(address(token), amount);
  }

  function test_withdraw_failure_message(uint amount) public {
    TestToken token = new TestToken(address(this),"Withdrawable","WDBL",18);
    vm.assume(amount > 0);
    deal(address(token), address(mgv), amount - 1);
    vm.expectRevert("mgv/withdrawERC20Fail");
    mgv.withdrawERC20(address(token), amount);
  }

  function test_marketOrderByPrice_extrema() public {
    vm.expectRevert("mgv/mOrder/maxPrice/tooHigh");
    mgv.marketOrderByPrice(olKey, LogPriceLib.MAX_PRICE_E18 + 1, 100, true);
    vm.expectRevert("mgv/mOrder/maxPrice/tooLow");
    mgv.marketOrderByPrice(olKey, LogPriceLib.MIN_PRICE_E18 - 1, 100, true);
  }

  function test_marketOrderByLogPrice_extrema() public {
    int highLogPrice = LogPriceLib.fromTick(Tick.wrap(MAX_TICK + 1), olKey.tickScale);
    vm.expectRevert("mgv/mOrder/logPrice/outOfRange");
    mgv.marketOrderByLogPrice(olKey, highLogPrice, 100, true);
    int lowLogPrice = LogPriceLib.fromTick(Tick.wrap(MIN_TICK - 1), olKey.tickScale);
    vm.expectRevert("mgv/mOrder/logPrice/outOfRange");
    mgv.marketOrderByLogPrice(olKey, lowLogPrice, 100, true);
  }

  function test_marketOrderForByPrice_extrema() public {
    vm.expectRevert("mgv/mOrder/maxPrice/tooHigh");
    mgv.marketOrderForByPrice(olKey, LogPriceLib.MAX_PRICE_E18 + 1, 100, true, address(this));
    vm.expectRevert("mgv/mOrder/maxPrice/tooLow");
    mgv.marketOrderForByPrice(olKey, LogPriceLib.MIN_PRICE_E18 - 1, 100, true, address(this));
  }

  function test_marketOrderForByLogPrice_extrema() public {
    int highLogPrice = LogPriceLib.fromTick(Tick.wrap(MAX_TICK + 1), olKey.tickScale);
    vm.expectRevert("mgv/mOrder/logPrice/outOfRange");
    mgv.marketOrderForByLogPrice(olKey, highLogPrice, 100, true, address(this));
    int lowLogPrice = LogPriceLib.fromTick(Tick.wrap(MIN_TICK - 1), olKey.tickScale);
    vm.expectRevert("mgv/mOrder/logPrice/outOfRange");
    mgv.marketOrderForByLogPrice(olKey, lowLogPrice, 100, true, address(this));
  }
}
