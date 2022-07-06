// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;
pragma abicoder v2;

import "mgv_test/lib/MangroveTest.sol";

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

    tkr = setupTaker($(base), $(quote), "taker[$(A),$(B)]");
    mkr = setupMaker($(base), $(quote), "maker[$(A),$(B)]");
    dual_mkr = setupMaker($(quote), $(base), "maker[$(B),$(A)]");

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
    mgv.setFee($(base), $(quote), 0);

    expectFrom($(mgv));
    emit SetFee($(base), $(quote), 1);
    vm.prank(notAdmin);
    mgv.setFee($(base), $(quote), 1);
  }

  function test_only_gov_can_set_fee() public {
    vm.expectRevert("mgv/unauthorized");
    vm.prank(notAdmin);
    mgv.setFee($(base), $(quote), 0);
  }

  function test_only_gov_can_set_density() public {
    vm.expectRevert("mgv/unauthorized");
    vm.prank(notAdmin);
    mgv.setDensity($(base), $(quote), 0);
  }

  function test_set_zero_density() public {
    expectFrom($(mgv));
    emit SetDensity($(base), $(quote), 0);
    mgv.setDensity($(base), $(quote), 0);
  }

  function test_only_gov_can_kill() public {
    vm.expectRevert("mgv/unauthorized");
    vm.prank(notAdmin);
    mgv.kill();
  }

  function test_killing_updates_config() public {
    (P.Global.t global, ) = mgv.config(address(0), address(0));
    assertTrue(!global.dead(), "mgv should not be dead ");
    expectFrom($(mgv));
    emit Kill();
    mgv.kill();
    (global, ) = mgv.config(address(0), address(0));
    assertTrue(global.dead(), "mgv should be dead ");
  }

  function test_kill_is_idempotent() public {
    (P.Global.t global, ) = mgv.config(address(0), address(0));
    assertTrue(!global.dead(), "mgv should not be dead ");
    expectFrom($(mgv));
    emit Kill();
    mgv.kill();
    (global, ) = mgv.config(address(0), address(0));
    assertTrue(global.dead(), "mgv should be dead");
    expectFrom($(mgv));
    emit Kill();
    mgv.kill();
    (global, ) = mgv.config(address(0), address(0));
    assertTrue(global.dead(), "mgv should still be dead");
  }

  function test_only_gov_can_set_vault() public {
    vm.expectRevert("mgv/unauthorized");
    vm.prank(notAdmin);
    mgv.setVault($(this));
  }

  function test_only_gov_can_set_monitor() public {
    vm.expectRevert("mgv/unauthorized");
    vm.prank(notAdmin);
    mgv.setMonitor($(this));
  }

  function test_only_gov_can_set_active() public {
    vm.expectRevert("mgv/unauthorized");
    vm.prank(notAdmin);
    mgv.activate($(quote), $(base), 0, 100, 0);
  }

  function test_only_gov_can_set_gasprice() public {
    vm.expectRevert("mgv/unauthorized");
    vm.prank(notAdmin);
    mgv.setGasprice(0);
  }

  function test_only_gov_can_set_gasmax() public {
    vm.expectRevert("mgv/unauthorized");
    vm.prank(notAdmin);
    mgv.setGasmax(0);
  }

  function test_only_gov_can_set_gasbase() public {
    vm.expectRevert("mgv/unauthorized");
    vm.prank(notAdmin);
    mgv.setGasbase($(base), $(quote), 0);
  }

  function test_empty_mgv_ok() public {
    tkr.marketOrder(0, 0);
  }

  function test_set_fee_ceiling() public {
    vm.expectRevert("mgv/config/fee/<=500");
    mgv.setFee($(base), $(quote), 501);
  }

  function test_set_density_ceiling() public {
    vm.expectRevert("mgv/config/density/112bits");
    mgv.setDensity($(base), $(quote), uint(type(uint112).max) + 1);
  }

  function test_set_gasprice_ceiling() public {
    vm.expectRevert("mgv/config/gasprice/16bits");
    mgv.setGasprice(uint(type(uint16).max) + 1);
  }

  function test_set_zero_gasbase() public {
    mgv.setGasbase($(base), $(quote), 0);
  }

  function test_set_gasbase_ceiling() public {
    vm.expectRevert("mgv/config/offer_gasbase/24bits");
    mgv.setGasbase($(base), $(quote), uint(type(uint24).max) + 1);
  }

  function test_set_gasmax_ceiling() public {
    vm.expectRevert("mgv/config/gasmax/24bits");
    mgv.setGasmax(uint(type(uint24).max) + 1);
  }

  function test_makerWants_wider_than_96_bits_fails_newOffer() public {
    vm.expectRevert("mgv/writeOffer/wants/96bits");
    mkr.newOffer(2**96, 1 ether, 10_000, 0);
  }

  function test_retractOffer_wrong_owner_fails() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 10_000, 0);
    vm.expectRevert("mgv/retractOffer/unauthorized");
    mgv.retractOffer($(base), $(quote), ofr, false);
  }

  function test_makerGives_wider_than_96_bits_fails_newOffer() public {
    vm.expectRevert("mgv/writeOffer/gives/96bits");
    mkr.newOffer(1, 2**96, 10_000, 0);
  }

  function test_makerGasreq_wider_than_24_bits_fails_newOffer() public {
    vm.expectRevert("mgv/writeOffer/gasreq/tooHigh");
    mkr.newOffer(1, 1, 2**24, 0);
  }

  function test_makerGasreq_bigger_than_gasmax_fails_newOffer() public {
    (P.Global.t cfg, ) = mgv.config($(base), $(quote));
    vm.expectRevert("mgv/writeOffer/gasreq/tooHigh");
    mkr.newOffer(1, 1, cfg.gasmax() + 1, 0);
  }

  function test_makerGasreq_at_gasmax_succeeds_newOffer() public {
    (P.Global.t cfg, ) = mgv.config($(base), $(quote));
    // Logging tests
    expectFrom($(mgv));
    emit OfferWrite(
      $(base),
      $(quote),
      address(mkr),
      1 ether, //base
      1 ether, //quote
      cfg.gasprice(), //gasprice
      cfg.gasmax(), //gasreq
      1, //ofrId
      0 // prev
    );
    expectFrom($(mgv));
    emit Debit(address(mkr), getProvision($(base), $(quote), cfg.gasmax(), 0));
    uint ofr = mkr.newOffer(1 ether, 1 ether, cfg.gasmax(), 0);
    assertTrue(
      mgv.isLive(mgv.offers($(base), $(quote), ofr)),
      "Offer should have been inserted"
    );
  }

  function test_makerGasreq_lower_than_density_fails_newOffer() public {
    mgv.setDensity($(base), $(quote), 100);
    (, P.Local.t cfg) = mgv.config($(base), $(quote));
    uint amount = (1 + cfg.offer_gasbase()) * cfg.density();
    vm.expectRevert("mgv/writeOffer/density/tooLow");
    mkr.newOffer(amount - 1, amount - 1, 1, 0);
  }

  function test_makerGasreq_at_density_suceeds() public {
    mgv.setDensity($(base), $(quote), 100);
    (P.Global.t glob, P.Local.t cfg) = mgv.config($(base), $(quote));
    uint amount = (1 + cfg.offer_gasbase()) * cfg.density();
    // Logging tests
    expectFrom($(mgv));
    emit OfferWrite(
      $(base),
      $(quote),
      address(mkr),
      amount, //base
      amount, //quote
      glob.gasprice(), //gasprice
      1, //gasreq
      1, //ofrId
      0 // prev
    );
    expectFrom($(mgv));
    emit Debit(address(mkr), getProvision($(base), $(quote), 1, 0));
    uint ofr = mkr.newOffer(amount, amount, 1, 0);
    assertTrue(
      mgv.isLive(mgv.offers($(base), $(quote), ofr)),
      "Offer should have been inserted"
    );
  }

  function test_makerGasprice_wider_than_16_bits_fails_newOffer() public {
    vm.expectRevert("mgv/writeOffer/gasprice/16bits");
    mkr.newOffer(1, 1, 1, 2**16, 0);
  }

  function test_takerWants_wider_than_160_bits_fails_marketOrder() public {
    vm.expectRevert("mgv/mOrder/takerWants/160bits");
    tkr.marketOrder(2**160, 0);
  }

  function test_takerWants_above_96bits_fails_snipes() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    uint[4][] memory targets = wrap_dynamic(
      [ofr, uint(type(uint96).max) + 1, type(uint96).max, type(uint).max]
    );
    vm.expectRevert("mgv/snipes/takerWants/96bits");
    mgv.snipes($(base), $(quote), targets, true);
  }

  function test_takerGives_above_96bits_fails_snipes() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    uint[4][] memory targets = wrap_dynamic(
      [ofr, type(uint96).max, uint(type(uint96).max) + 1, type(uint).max]
    );
    vm.expectRevert("mgv/snipes/takerGives/96bits");
    mgv.snipes($(base), $(quote), targets, true);
  }

  function test_initial_allowance_is_zero() public {
    assertEq(
      mgv.allowances($(base), $(quote), address(tkr), $(this)),
      0,
      "initial allowance should be 0"
    );
  }

  function test_cannot_snipesFor_for_without_allowance() public {
    deal($(base), address(mkr), 1 ether);
    mkr.approveMgv(base, 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);

    vm.expectRevert("mgv/lowAllowance");
    mgv.snipesFor(
      $(base),
      $(quote),
      wrap_dynamic([ofr, 1 ether, 1 ether, 300_000]),
      true,
      address(tkr)
    );
  }

  function test_cannot_marketOrderFor_for_without_allowance() public {
    deal($(base), address(mkr), 1 ether);
    mkr.approveMgv(base, 1 ether);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    vm.expectRevert("mgv/lowAllowance");
    mgv.marketOrderFor($(base), $(quote), 1 ether, 1 ether, true, address(tkr));
  }

  function test_can_marketOrderFor_for_with_allowance() public {
    deal($(base), address(mkr), 1 ether);
    mkr.approveMgv(base, 1 ether);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    tkr.approveSpender($(this), 1.2 ether);
    uint takerGot;
    (takerGot, , , ) = mgv.marketOrderFor(
      $(base),
      $(quote),
      1 ether,
      1 ether,
      true,
      address(tkr)
    );
    assertEq(
      mgv.allowances($(base), $(quote), address(tkr), $(this)),
      0.2 ether,
      "allowance should have correctly reduced"
    );
  }

  /* # Internal IMaker setup */

  bytes trade_cb;
  bytes posthook_cb;

  // maker's trade fn for the mgv
  function makerExecute(MgvLib.SingleOrder calldata)
    external
    override
    returns (bytes32 ret)
  {
    ret; // silence unused function parameter
    bool success;
    if (trade_cb.length > 0) {
      (success, ) = $(this).call(trade_cb);
      assertTrue(success, "makerExecute callback must work");
    }
    return "";
  }

  function makerPosthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata result
  ) external override {
    bool success;
    order; // silence compiler warning
    if (posthook_cb.length > 0) {
      (success, ) = $(this).call(posthook_cb);
      bool tradeResult = (result.mgvData == "mgv/tradeSuccess");
      assertTrue(success == tradeResult, "makerPosthook callback must work");
    }
  }

  /* # Reentrancy */

  /* New Offer failure */

  function newOfferKO() external {
    vm.expectRevert("mgv/reentrancyLocked");
    mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 30_000, 0, 0);
  }

  function test_newOffer_on_reentrancy_fails() public {
    uint ofr = mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 100_000, 0, 0);
    trade_cb = abi.encodeCall(this.newOfferKO, ());
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
  }

  /* New Offer success */

  // ! may be called with inverted _base and _quote
  function newOfferOK(address _base, address _quote) external {
    mgv.newOffer(_base, _quote, 1 ether, 1 ether, 30_000, 0, 0);
  }

  function test_newOffer_on_reentrancy_succeeds() public {
    uint ofr = mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 200_000, 0, 0);
    trade_cb = abi.encodeCall(this.newOfferOK, ($(quote), $(base)));
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    assertTrue(
      mgv.best($(quote), $(base)) == 1,
      "newOffer on swapped pair must work"
    );
  }

  function test_newOffer_on_posthook_succeeds() public {
    uint ofr = mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 200_000, 0, 0);
    posthook_cb = abi.encodeCall(this.newOfferOK, ($(base), $(quote)));
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    assertTrue(
      mgv.best($(base), $(quote)) == 2,
      "newOffer on posthook must work"
    );
  }

  /* Update offer failure */

  function updateOfferKO(uint ofr) external {
    vm.expectRevert("mgv/reentrancyLocked");
    mgv.updateOffer($(base), $(quote), 1 ether, 2 ether, 35_000, 0, 0, ofr);
  }

  function test_updateOffer_on_reentrancy_fails() public {
    uint ofr = mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 100_000, 0, 0);
    trade_cb = abi.encodeCall(this.updateOfferKO, (ofr));
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
  }

  /* Update offer success */

  // ! may be called with inverted _base and _quote
  function updateOfferOK(
    address _base,
    address _quote,
    uint ofr
  ) external {
    mgv.updateOffer(_base, _quote, 1 ether, 2 ether, 35_000, 0, 0, ofr);
  }

  function test_updateOffer_on_reentrancy_succeeds() public {
    uint other_ofr = mgv.newOffer(
      $(quote),
      $(base),
      1 ether,
      1 ether,
      100_000,
      0,
      0
    );

    trade_cb = abi.encodeCall(
      this.updateOfferOK,
      ($(quote), $(base), other_ofr)
    );
    uint ofr = mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 400_000, 0, 0);
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    assertTrue(
      mgv.offerDetails($(quote), $(base), other_ofr).gasreq() == 35_000,
      "updateOffer on swapped pair must work"
    );
  }

  function test_updateOffer_on_posthook_succeeds() public {
    uint other_ofr = mgv.newOffer(
      $(base),
      $(quote),
      1 ether,
      1 ether,
      100_000,
      0,
      0
    );
    posthook_cb = abi.encodeCall(
      this.updateOfferOK,
      ($(base), $(quote), other_ofr)
    );
    uint ofr = mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 300_000, 0, 0);
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    assertTrue(
      mgv.offerDetails($(base), $(quote), other_ofr).gasreq() == 35_000,
      "updateOffer on posthook must work"
    );
  }

  /* Cancel Offer failure */

  function retractOfferKO(uint id) external {
    vm.expectRevert("mgv/reentrancyLocked");
    mgv.retractOffer($(base), $(quote), id, false);
  }

  function test_retractOffer_on_reentrancy_fails() public {
    uint ofr = mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 100_000, 0, 0);
    trade_cb = abi.encodeCall(this.retractOfferKO, (ofr));
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
  }

  /* Cancel Offer success */

  function retractOfferOK(
    address _base,
    address _quote,
    uint id
  ) external {
    uint collected = mgv.retractOffer(_base, _quote, id, false);
    assertEq(
      collected,
      0,
      "Unexpected collected provision after retract w/o deprovision"
    );
  }

  function test_retractOffer_on_reentrancy_succeeds() public {
    uint other_ofr = mgv.newOffer(
      $(quote),
      $(base),
      1 ether,
      1 ether,
      90_000,
      0,
      0
    );
    trade_cb = abi.encodeCall(
      this.retractOfferOK,
      ($(quote), $(base), other_ofr)
    );

    uint ofr = mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 90_000, 0, 0);
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    assertTrue(
      mgv.best($(quote), $(base)) == 0,
      "retractOffer on swapped pair must work"
    );
  }

  function test_retractOffer_on_posthook_succeeds() public {
    uint other_ofr = mgv.newOffer(
      $(base),
      $(quote),
      1 ether,
      1 ether,
      190_000,
      0,
      0
    );
    posthook_cb = abi.encodeCall(
      this.retractOfferOK,
      ($(base), $(quote), other_ofr)
    );

    uint ofr = mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 90_000, 0, 0);
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    assertTrue(
      mgv.best($(base), $(quote)) == 0,
      "retractOffer on posthook must work"
    );
  }

  /* Market Order failure */

  function marketOrderKO() external {
    vm.expectRevert("mgv/reentrancyLocked");
    mgv.marketOrder($(base), $(quote), 0.2 ether, 0.2 ether, true);
  }

  function test_marketOrder_on_reentrancy_fails() public {
    uint ofr = mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 100_000, 0, 0);
    trade_cb = abi.encodeCall(this.marketOrderKO, ());
    assertTrue(tkr.take(ofr, 0.1 ether), "take must succeed or test is void");
  }

  /* Market Order Success */

  function marketOrderOK(address _base, address _quote) external {
    mgv.marketOrder(_base, _quote, 0.5 ether, 0.5 ether, true);
  }

  function test_marketOrder_on_reentrancy_succeeds() public {
    dual_mkr.newOffer(0.5 ether, 0.5 ether, 30_000, 0);
    uint ofr = mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 392_000, 0, 0);
    trade_cb = abi.encodeCall(this.marketOrderOK, ($(quote), $(base)));
    assertTrue(tkr.take(ofr, 0.1 ether), "take must succeed or test is void");
    assertTrue(
      mgv.best($(quote), $(base)) == 0,
      "2nd market order must have emptied mgv"
    );
  }

  function test_marketOrder_on_posthook_succeeds() public {
    uint ofr = mgv.newOffer(
      $(base),
      $(quote),
      0.5 ether,
      0.5 ether,
      500_000,
      0,
      0
    );
    mgv.newOffer($(base), $(quote), 0.5 ether, 0.5 ether, 200_000, 0, 0);
    posthook_cb = abi.encodeCall(this.marketOrderOK, ($(base), $(quote)));
    assertTrue(tkr.take(ofr, 0.6 ether), "take must succeed or test is void");
    assertTrue(
      mgv.best($(base), $(quote)) == 0,
      "2nd market order must have emptied mgv"
    );
  }

  /* Snipe failure */

  function snipesKO(uint id) external {
    uint[4][] memory targets = wrap_dynamic(
      [id, 1 ether, type(uint96).max, type(uint48).max]
    );
    vm.expectRevert("mgv/reentrancyLocked");
    mgv.snipes($(base), $(quote), targets, true);
  }

  function test_snipe_on_reentrancy_fails() public {
    uint ofr = mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 60_000, 0, 0);
    trade_cb = abi.encodeCall(this.snipesKO, (ofr));
    assertTrue(tkr.take(ofr, 0.1 ether), "take must succeed or test is void");
  }

  /* Snipe success */

  function snipesOK(
    address _base,
    address _quote,
    uint id
  ) external {
    uint[4][] memory targets = wrap_dynamic(
      [id, 1 ether, type(uint96).max, type(uint48).max]
    );
    mgv.snipes(_base, _quote, targets, true);
  }

  function test_snipes_on_reentrancy_succeeds() public {
    uint other_ofr = dual_mkr.newOffer(1 ether, 1 ether, 30_000, 0);
    trade_cb = abi.encodeCall(this.snipesOK, ($(quote), $(base), other_ofr));

    uint ofr = mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 190_000, 0, 0);
    assertTrue(tkr.take(ofr, 0.1 ether), "take must succeed or test is void");
    assertTrue(
      mgv.best($(quote), $(base)) == 0,
      "snipe in swapped pair must work"
    );
  }

  function test_snipes_on_posthook_succeeds() public {
    uint other_ofr = mkr.newOffer(1 ether, 1 ether, 30_000, 0);
    posthook_cb = abi.encodeCall(this.snipesOK, ($(base), $(quote), other_ofr));

    uint ofr = mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 190_000, 0, 0);
    assertTrue(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    assertTrue(mgv.best($(base), $(quote)) == 0, "snipe in posthook must work");
  }

  function test_newOffer_on_closed_fails() public {
    mgv.kill();
    vm.expectRevert("mgv/dead");
    mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 0, 0, 0);
  }

  /* # Mangrove closed/inactive */

  function test_take_on_closed_fails() public {
    uint ofr = mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 0, 0, 0);

    mgv.kill();
    vm.expectRevert("mgv/dead");
    tkr.take(ofr, 1 ether);
  }

  function test_newOffer_on_inactive_fails() public {
    mgv.deactivate($(base), $(quote));
    vm.expectRevert("mgv/inactive");
    mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 0, 0, 0);
  }

  function test_receive_on_closed_fails() public {
    mgv.kill();

    (bool success, bytes memory retdata) = $(mgv).call{value: 10 ether}("");
    if (success) {
      fail("receive() should fail on closed market");
    } else {
      string memory r = getReason(retdata);
      revertEq(r, "mgv/dead");
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
    uint ofr = mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 0, 0, 0);
    mgv.kill();
    mgv.retractOffer($(base), $(quote), ofr, false);
  }

  function test_updateOffer_on_closed_fails() public {
    uint ofr = mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 0, 0, 0);
    mgv.kill();
    vm.expectRevert("mgv/dead");
    mgv.updateOffer($(base), $(quote), 1 ether, 1 ether, 0, 0, 0, ofr);
  }

  function test_activation_emits_events_in_order() public {
    expectFrom($(mgv));
    emit SetActive($(quote), $(base), true);
    expectFrom($(mgv));
    emit SetFee($(quote), $(base), 7);
    expectFrom($(mgv));
    emit SetDensity($(quote), $(base), 0);
    expectFrom($(mgv));
    emit SetGasbase($(quote), $(base), 3);
    mgv.activate($(quote), $(base), 7, 0, 3);
  }

  function test_updateOffer_on_inactive_fails() public {
    uint ofr = mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 0, 0, 0);
    expectFrom($(mgv));
    emit SetActive($(base), $(quote), false);
    mgv.deactivate($(base), $(quote));
    vm.expectRevert("mgv/inactive");
    mgv.updateOffer($(base), $(quote), 1 ether, 1 ether, 0, 0, 0, ofr);
  }
}
