// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;
pragma abicoder v2;

import "mgv_test/lib/MangroveTest.sol";

contract NotAdmin {
  AbstractMangrove mgv;

  constructor(AbstractMangrove _mgv) {
    mgv = _mgv;
  }

  function setGasprice(uint value) public {
    mgv.setGasprice(value);
  }

  function setFee(
    address base,
    address quote,
    uint fee
  ) public {
    mgv.setFee(base, quote, fee);
  }

  function setGovernance(address newGovernance) public {
    mgv.setGovernance(newGovernance);
  }

  function kill() public {
    mgv.kill();
  }

  function activate(
    address base,
    address quote,
    uint fee,
    uint density,
    uint offer_gasbase
  ) public {
    mgv.activate(base, quote, fee, density, offer_gasbase);
  }

  function setGasbase(
    address base,
    address quote,
    uint offer_gasbase
  ) public {
    mgv.setGasbase(base, quote, offer_gasbase);
  }

  function setGasmax(uint value) public {
    mgv.setGasmax(value);
  }

  function setDensity(
    address base,
    address quote,
    uint value
  ) public {
    mgv.setDensity(base, quote, value);
  }

  function setVault(address value) public {
    mgv.setVault(value);
  }

  function setMonitor(address value) public {
    mgv.setMonitor(value);
  }
}

contract Deployer is MangroveTest {
  function deploy() public returns (AbstractMangrove) {
    return new Mangrove({governance: msg.sender, gasprice: 0, gasmax: 0});
  }
}

// In these tests, the testing contract is the market maker.
contract GatekeepingTest is IMaker, MangroveTest {
  receive() external payable {}

  TestTaker tkr;
  TestMaker mkr;
  TestMaker dual_mkr;

  function setUp() public override {
    super.setUp();

    tkr = setupTaker($base, $quote, "taker[$A,$B]");
    mkr = setupMaker($base, $quote, "maker[$A,$B]");
    dual_mkr = setupMaker($quote, $base, "maker[$B,$A]");

    mkr.provisionMgv(5 ether);
    dual_mkr.provisionMgv(5 ether);

    deal($quote, address(tkr), 1 ether);
    deal($quote, address(mkr), 1 ether);
    deal($base, address(dual_mkr), 1 ether);

    tkr.approveMgv(quote, 1 ether);
  }

  /* # Test Config */

  function test_gov_is_not_sender() public {
    AbstractMangrove new_mgv = (new Deployer()).deploy();

    assertEq(new_mgv.governance(), $this, "governance should return this");
  }

  function test_gov_cant_be_zero() public {
    try mgv.setGovernance(address(0)) {
      fail("setting gov to 0 should be impossible");
    } catch Error(string memory r) {
      revertEq(r, "mgv/config/gov/not0");
    }
  }

  function test_gov_can_transfer_rights() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    // Logging tests
    expectFrom($mgv);
    emit SetGovernance(address(notAdmin));
    mgv.setGovernance(address(notAdmin));

    try mgv.setFee($base, $quote, 0) {
      fail("testing contracts should no longer be admin");
    } catch {}

    expectFrom($mgv);
    emit SetFee($base, $quote, 1);
    try notAdmin.setFee($base, $quote, 1) {} catch {
      fail("notAdmin should have been given admin rights");
    }
  }

  function test_only_gov_can_set_fee() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    try notAdmin.setFee($base, $quote, 0) {
      fail("nonadmin cannot set fee");
    } catch Error(string memory r) {
      revertEq(r, "mgv/unauthorized");
    }
  }

  function test_only_gov_can_set_density() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    try notAdmin.setDensity($base, $quote, 0) {
      fail("nonadmin cannot set density");
    } catch Error(string memory r) {
      revertEq(r, "mgv/unauthorized");
    }
  }

  function test_set_zero_density() public {
    // Logging tests
    expectFrom($mgv);
    emit SetDensity($base, $quote, 0);
    try mgv.setDensity($base, $quote, 0) {} catch Error(string memory) {
      fail("setting density to 0 should work");
    }
  }

  function test_only_gov_can_kill() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    try notAdmin.kill() {
      fail("nonadmin cannot kill");
    } catch Error(string memory r) {
      revertEq(r, "mgv/unauthorized");
    }
  }

  function test_killing_updates_config() public {
    (P.Global.t global, ) = mgv.config(address(0), address(0));
    assertTrue(!global.dead(), "mgv should not be dead ");
    expectFrom($mgv);
    emit Kill();
    mgv.kill();
    (global, ) = mgv.config(address(0), address(0));
    assertTrue(global.dead(), "mgv should be dead ");
    // Logging tests
  }

  function test_kill_is_idempotent() public {
    (P.Global.t global, ) = mgv.config(address(0), address(0));
    assertTrue(!global.dead(), "mgv should not be dead ");
    expectFrom($mgv);
    emit Kill();
    mgv.kill();
    (global, ) = mgv.config(address(0), address(0));
    assertTrue(global.dead(), "mgv should be dead");
    expectFrom($mgv);
    emit Kill();
    mgv.kill();
    (global, ) = mgv.config(address(0), address(0));
    assertTrue(global.dead(), "mgv should still be dead");
    // Logging tests
  }

  function test_only_gov_can_set_vault() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    try notAdmin.setVault($this) {
      fail("nonadmin cannot set vault");
    } catch Error(string memory r) {
      revertEq(r, "mgv/unauthorized");
    }
  }

  function test_only_gov_can_set_monitor() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    try notAdmin.setMonitor($this) {
      fail("nonadmin cannot set monitor");
    } catch Error(string memory r) {
      revertEq(r, "mgv/unauthorized");
    }
  }

  function test_only_gov_can_set_active() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    try notAdmin.activate($quote, $base, 0, 100, 0) {
      fail("nonadmin cannot set active");
    } catch Error(string memory r) {
      revertEq(r, "mgv/unauthorized");
    }
  }

  function test_only_gov_can_set_gasprice() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    try notAdmin.setGasprice(0) {
      fail("nonadmin cannot set gasprice");
    } catch Error(string memory r) {
      revertEq(r, "mgv/unauthorized");
    }
  }

  function test_only_gov_can_set_gasmax() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    try notAdmin.setGasmax(0) {
      fail("nonadmin cannot set gasmax");
    } catch Error(string memory r) {
      revertEq(r, "mgv/unauthorized");
    }
  }

  function test_only_gov_can_set_gasbase() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    try notAdmin.setGasbase($base, $quote, 0) {
      fail("nonadmin cannot set gasbase");
    } catch Error(string memory r) {
      revertEq(r, "mgv/unauthorized");
    }
  }

  function test_empty_mgv_ok() public {
    try tkr.marketOrder(0, 0) {} catch {
      fail("market order on empty mgv should not fail");
    }
    // Logging tests
  }

  function test_set_fee_ceiling() public {
    try mgv.setFee($base, $quote, 501) {} catch Error(string memory r) {
      revertEq(r, "mgv/config/fee/<=500");
    }
  }

  function test_set_density_ceiling() public {
    try mgv.setDensity($base, $quote, uint(type(uint112).max) + 1) {
      fail("density above ceiling should fail");
    } catch Error(string memory r) {
      revertEq(r, "mgv/config/density/112bits");
    }
  }

  function test_set_gasprice_ceiling() public {
    try mgv.setGasprice(uint(type(uint16).max) + 1) {
      fail("gasprice above ceiling should fail");
    } catch Error(string memory r) {
      revertEq(r, "mgv/config/gasprice/16bits");
    }
  }

  function test_set_zero_gasbase() public {
    try mgv.setGasbase($base, $quote, 0) {} catch Error(string memory) {
      fail("setting gasbases to 0 should work");
    }
  }

  function test_set_gasbase_ceiling() public {
    try mgv.setGasbase($base, $quote, uint(type(uint24).max) + 1) {
      fail("offer_gasbase above ceiling should fail");
    } catch Error(string memory r) {
      revertEq(r, "mgv/config/offer_gasbase/24bits");
    }
  }

  function test_set_gasmax_ceiling() public {
    try mgv.setGasmax(uint(type(uint24).max) + 1) {
      fail("gasmax above ceiling should fail");
    } catch Error(string memory r) {
      revertEq(r, "mgv/config/gasmax/24bits");
    }
  }

  function test_makerWants_wider_than_96_bits_fails_newOffer() public {
    try mkr.newOffer(2**96, 1 ether, 10_000, 0) {
      fail("Too wide offer should not be inserted");
    } catch Error(string memory r) {
      assertEq(r, "mgv/writeOffer/wants/96bits", "wrong revert reason");
    }
  }

  function test_retractOffer_wrong_owner_fails() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 10_000, 0);
    try mgv.retractOffer($base, $quote, ofr, false) {
      fail("Too wide offer should not be inserted");
    } catch Error(string memory r) {
      assertEq(r, "mgv/retractOffer/unauthorized", "wrong revert reason");
    }
  }

  function test_makerGives_wider_than_96_bits_fails_newOffer() public {
    try mkr.newOffer(1, 2**96, 10_000, 0) {
      fail("Too wide offer should not be inserted");
    } catch Error(string memory r) {
      assertEq(r, "mgv/writeOffer/gives/96bits", "wrong revert reason");
    }
  }

  function test_makerGasreq_wider_than_24_bits_fails_newOffer() public {
    try mkr.newOffer(1, 1, 2**24, 0) {
      fail("Too wide offer should not be inserted");
    } catch Error(string memory r) {
      assertEq(r, "mgv/writeOffer/gasreq/tooHigh", "wrong revert reason");
    }
  }

  function test_makerGasreq_bigger_than_gasmax_fails_newOffer() public {
    (P.Global.t cfg, ) = mgv.config($base, $quote);
    try mkr.newOffer(1, 1, cfg.gasmax() + 1, 0) {
      fail("Offer should not be inserted");
    } catch Error(string memory r) {
      assertEq(r, "mgv/writeOffer/gasreq/tooHigh", "wrong revert reason");
    }
  }

  function test_makerGasreq_at_gasmax_succeeds_newOffer() public {
    (P.Global.t cfg, ) = mgv.config($base, $quote);
    // Logging tests
    expectFrom($mgv);
    emit OfferWrite(
      $base,
      $quote,
      address(mkr),
      1 ether, //base
      1 ether, //quote
      cfg.gasprice(), //gasprice
      cfg.gasmax(), //gasreq
      1, //ofrId
      0 // prev
    );
    expectFrom($mgv);
    emit Debit(address(mkr), getProvision($base, $quote, cfg.gasmax(), 0));
    try mkr.newOffer(1 ether, 1 ether, cfg.gasmax(), 0) returns (uint ofr) {
      assertTrue(
        mgv.isLive(mgv.offers($base, $quote, ofr)),
        "Offer should have been inserted"
      );
    } catch {
      fail("Offer at gasmax should pass");
    }
  }

  function test_makerGasreq_lower_than_density_fails_newOffer() public {
    mgv.setDensity($base, $quote, 100);
    (, P.Local.t cfg) = mgv.config($base, $quote);
    uint amount = (1 + cfg.offer_gasbase()) * cfg.density();
    try mkr.newOffer(amount - 1, amount - 1, 1, 0) {
      fail("Offer should not be inserted");
    } catch Error(string memory r) {
      assertEq(r, "mgv/writeOffer/density/tooLow", "wrong revert reason");
    }
  }

  function test_makerGasreq_at_density_suceeds() public {
    mgv.setDensity($base, $quote, 100);
    (P.Global.t glob, P.Local.t cfg) = mgv.config($base, $quote);
    uint amount = (1 + cfg.offer_gasbase()) * cfg.density();
    // Logging tests
    expectFrom($mgv);
    emit OfferWrite(
      $base,
      $quote,
      address(mkr),
      amount, //base
      amount, //quote
      glob.gasprice(), //gasprice
      1, //gasreq
      1, //ofrId
      0 // prev
    );
    expectFrom($mgv);
    emit Debit(address(mkr), getProvision($base, $quote, 1, 0));
    try mkr.newOffer(amount, amount, 1, 0) returns (uint ofr) {
      assertTrue(
        mgv.isLive(mgv.offers($base, $quote, ofr)),
        "Offer should have been inserted"
      );
    } catch {
      fail("Offer at density should pass");
    }
  }

  function test_makerGasprice_wider_than_16_bits_fails_newOffer() public {
    try mkr.newOffer(1, 1, 1, 2**16, 0) {
      fail("Too wide offer should not be inserted");
    } catch Error(string memory r) {
      assertEq(r, "mgv/writeOffer/gasprice/16bits", "wrong revert reason");
    }
  }

  function test_takerWants_wider_than_160_bits_fails_marketOrder() public {
    try tkr.marketOrder(2**160, 0) {
      fail("takerWants > 160bits, order should fail");
    } catch Error(string memory r) {
      assertEq(r, "mgv/mOrder/takerWants/160bits", "wrong revert reason");
    }
  }

  function test_takerWants_above_96bits_fails_snipes() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [
      ofr,
      uint(type(uint96).max) + 1,
      type(uint96).max,
      type(uint).max
    ];
    try mgv.snipes($base, $quote, targets, true) {
      fail("Snipes with takerWants > 96bits should fail");
    } catch Error(string memory reason) {
      revertEq(reason, "mgv/snipes/takerWants/96bits");
    }
  }

  function test_takerGives_above_96bits_fails_snipes() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [
      ofr,
      type(uint96).max,
      uint(type(uint96).max) + 1,
      type(uint).max
    ];
    try mgv.snipes($base, $quote, targets, true) {
      fail("Snipes with takerGives > 96bits should fail");
    } catch Error(string memory reason) {
      revertEq(reason, "mgv/snipes/takerGives/96bits");
    }
  }

  function test_initial_allowance_is_zero() public {
    assertEq(
      mgv.allowances($base, $quote, address(tkr), $this),
      0,
      "initial allowance should be 0"
    );
  }

  function test_cannot_snipesFor_for_without_allowance() public {
    deal($base, address(mkr), 1 ether);
    mkr.approveMgv(base, 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 300_000];
    try mgv.snipesFor($base, $quote, targets, true, address(tkr)) {
      fail("snipeFor should fail without allowance");
    } catch Error(string memory reason) {
      revertEq(reason, "mgv/lowAllowance");
    }
  }

  function test_cannot_marketOrderFor_for_without_allowance() public {
    deal($base, address(mkr), 1 ether);
    mkr.approveMgv(base, 1 ether);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    try
      mgv.marketOrderFor($base, $quote, 1 ether, 1 ether, true, address(tkr))
    {
      fail("marketOrderfor should fail without allowance");
    } catch Error(string memory reason) {
      revertEq(reason, "mgv/lowAllowance");
    }
  }

  function test_can_marketOrderFor_for_with_allowance() public {
    deal($base, address(mkr), 1 ether);
    mkr.approveMgv(base, 1 ether);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    tkr.approveSpender($this, 1.2 ether);
    uint takerGot;
    (takerGot, , , ) = mgv.marketOrderFor(
      $base,
      $quote,
      1 ether,
      1 ether,
      true,
      address(tkr)
    );
    assertEq(
      mgv.allowances($base, $quote, address(tkr), $this),
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
      (success, ) = $this.call(trade_cb);
      require(success, "makerExecute callback must work");
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
      (success, ) = $this.call(posthook_cb);
      bool tradeResult = (result.mgvData == "mgv/tradeSuccess");
      require(success == tradeResult, "makerPosthook callback must work");
    }
  }

  /* # Reentrancy */

  /* New Offer failure */

  function newOfferKO() external {
    try mgv.newOffer($base, $quote, 1 ether, 1 ether, 30_000, 0, 0) {
      fail("newOffer on same pair should fail");
    } catch Error(string memory reason) {
      revertEq(reason, "mgv/reentrancyLocked");
    }
  }

  function test_newOffer_on_reentrancy_fails() public {
    uint ofr = mgv.newOffer($base, $quote, 1 ether, 1 ether, 100_000, 0, 0);
    trade_cb = abi.encodeWithSelector(this.newOfferKO.selector);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
  }

  /* New Offer success */

  // ! may be called with inverted _base and _quote
  function newOfferOK(address _base, address _quote) external {
    mgv.newOffer(_base, _quote, 1 ether, 1 ether, 30_000, 0, 0);
  }

  function test_newOffer_on_reentrancy_succeeds() public {
    uint ofr = mgv.newOffer($base, $quote, 1 ether, 1 ether, 200_000, 0, 0);
    trade_cb = abi.encodeWithSelector(this.newOfferOK.selector, $quote, $base);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    require(mgv.best($quote, $base) == 1, "newOffer on swapped pair must work");
  }

  function test_newOffer_on_posthook_succeeds() public {
    uint ofr = mgv.newOffer($base, $quote, 1 ether, 1 ether, 200_000, 0, 0);
    posthook_cb = abi.encodeWithSelector(
      this.newOfferOK.selector,
      $base,
      $quote
    );
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    require(mgv.best($base, $quote) == 2, "newOffer on posthook must work");
  }

  /* Update offer failure */

  function updateOfferKO(uint ofr) external {
    try mgv.updateOffer($base, $quote, 1 ether, 2 ether, 35_000, 0, 0, ofr) {
      fail("update offer on same pair should fail");
    } catch Error(string memory reason) {
      revertEq(reason, "mgv/reentrancyLocked");
    }
  }

  function test_updateOffer_on_reentrancy_fails() public {
    uint ofr = mgv.newOffer($base, $quote, 1 ether, 1 ether, 100_000, 0, 0);
    trade_cb = abi.encodeWithSelector(this.updateOfferKO.selector, ofr);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
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
      $quote,
      $base,
      1 ether,
      1 ether,
      100_000,
      0,
      0
    );

    trade_cb = abi.encodeWithSelector(
      this.updateOfferOK.selector,
      $quote,
      $base,
      other_ofr
    );
    uint ofr = mgv.newOffer($base, $quote, 1 ether, 1 ether, 400_000, 0, 0);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    (, P.OfferDetailStruct memory od) = mgv.offerInfo($quote, $base, other_ofr);
    require(od.gasreq == 35_000, "updateOffer on swapped pair must work");
  }

  function test_updateOffer_on_posthook_succeeds() public {
    uint other_ofr = mgv.newOffer(
      $base,
      $quote,
      1 ether,
      1 ether,
      100_000,
      0,
      0
    );
    posthook_cb = abi.encodeWithSelector(
      this.updateOfferOK.selector,
      $base,
      $quote,
      other_ofr
    );
    uint ofr = mgv.newOffer($base, $quote, 1 ether, 1 ether, 300_000, 0, 0);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    (, P.OfferDetailStruct memory od) = mgv.offerInfo($base, $quote, other_ofr);
    require(od.gasreq == 35_000, "updateOffer on posthook must work");
  }

  /* Cancel Offer failure */

  function retractOfferKO(uint id) external {
    try mgv.retractOffer($base, $quote, id, false) {
      fail("retractOffer on same pair should fail");
    } catch Error(string memory reason) {
      revertEq(reason, "mgv/reentrancyLocked");
    }
  }

  function test_retractOffer_on_reentrancy_fails() public {
    uint ofr = mgv.newOffer($base, $quote, 1 ether, 1 ether, 100_000, 0, 0);
    trade_cb = abi.encodeWithSelector(this.retractOfferKO.selector, ofr);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
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
      $quote,
      $base,
      1 ether,
      1 ether,
      90_000,
      0,
      0
    );
    trade_cb = abi.encodeWithSelector(
      this.retractOfferOK.selector,
      $quote,
      $base,
      other_ofr
    );

    uint ofr = mgv.newOffer($base, $quote, 1 ether, 1 ether, 90_000, 0, 0);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    require(
      mgv.best($quote, $base) == 0,
      "retractOffer on swapped pair must work"
    );
  }

  function test_retractOffer_on_posthook_succeeds() public {
    uint other_ofr = mgv.newOffer(
      $base,
      $quote,
      1 ether,
      1 ether,
      190_000,
      0,
      0
    );
    posthook_cb = abi.encodeWithSelector(
      this.retractOfferOK.selector,
      $base,
      $quote,
      other_ofr
    );

    uint ofr = mgv.newOffer($base, $quote, 1 ether, 1 ether, 90_000, 0, 0);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    require(mgv.best($base, $quote) == 0, "retractOffer on posthook must work");
  }

  /* Market Order failure */

  function marketOrderKO() external {
    try mgv.marketOrder($base, $quote, 0.2 ether, 0.2 ether, true) {
      fail("marketOrder on same pair should fail");
    } catch Error(string memory reason) {
      revertEq(reason, "mgv/reentrancyLocked");
    }
  }

  function test_marketOrder_on_reentrancy_fails() public {
    uint ofr = mgv.newOffer($base, $quote, 1 ether, 1 ether, 100_000, 0, 0);
    trade_cb = abi.encodeWithSelector(this.marketOrderKO.selector);
    require(tkr.take(ofr, 0.1 ether), "take must succeed or test is void");
  }

  /* Market Order Success */

  function marketOrderOK(address _base, address _quote) external {
    try
      mgv.marketOrder(_base, _quote, 0.5 ether, 0.5 ether, true)
    {} catch Error(string memory r) {
      console.log("ERR", r);
    }
  }

  function test_marketOrder_on_reentrancy_succeeds() public {
    console.log(
      "dual mkr offer",
      dual_mkr.newOffer(0.5 ether, 0.5 ether, 30_000, 0)
    );
    uint ofr = mgv.newOffer($base, $quote, 1 ether, 1 ether, 392_000, 0, 0);
    console.log("normal offer", ofr);
    trade_cb = abi.encodeWithSelector(
      this.marketOrderOK.selector,
      $quote,
      $base
    );
    require(tkr.take(ofr, 0.1 ether), "take must succeed or test is void");
    require(
      mgv.best($quote, $base) == 0,
      "2nd market order must have emptied mgv"
    );
  }

  function test_marketOrder_on_posthook_succeeds() public {
    uint ofr = mgv.newOffer($base, $quote, 0.5 ether, 0.5 ether, 500_000, 0, 0);
    mgv.newOffer($base, $quote, 0.5 ether, 0.5 ether, 200_000, 0, 0);
    posthook_cb = abi.encodeWithSelector(
      this.marketOrderOK.selector,
      $base,
      $quote
    );
    require(tkr.take(ofr, 0.6 ether), "take must succeed or test is void");
    require(
      mgv.best($base, $quote) == 0,
      "2nd market order must have emptied mgv"
    );
  }

  /* Snipe failure */

  function snipesKO(uint id) external {
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [id, 1 ether, type(uint96).max, type(uint48).max];
    try mgv.snipes($base, $quote, targets, true) {
      fail("snipe on same pair should fail");
    } catch Error(string memory reason) {
      revertEq(reason, "mgv/reentrancyLocked");
    }
  }

  function test_snipe_on_reentrancy_fails() public {
    uint ofr = mgv.newOffer($base, $quote, 1 ether, 1 ether, 60_000, 0, 0);
    trade_cb = abi.encodeWithSelector(this.snipesKO.selector, ofr);
    require(tkr.take(ofr, 0.1 ether), "take must succeed or test is void");
  }

  /* Snipe success */

  function snipesOK(
    address _base,
    address _quote,
    uint id
  ) external {
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [id, 1 ether, type(uint96).max, type(uint48).max];
    mgv.snipes(_base, _quote, targets, true);
  }

  function test_snipes_on_reentrancy_succeeds() public {
    uint other_ofr = dual_mkr.newOffer(1 ether, 1 ether, 30_000, 0);
    trade_cb = abi.encodeWithSelector(
      this.snipesOK.selector,
      $quote,
      $base,
      other_ofr
    );

    uint ofr = mgv.newOffer($base, $quote, 1 ether, 1 ether, 190_000, 0, 0);
    require(tkr.take(ofr, 0.1 ether), "take must succeed or test is void");
    require(mgv.best($quote, $base) == 0, "snipe in swapped pair must work");
  }

  function test_snipes_on_posthook_succeeds() public {
    uint other_ofr = mkr.newOffer(1 ether, 1 ether, 30_000, 0);
    posthook_cb = abi.encodeWithSelector(
      this.snipesOK.selector,
      $base,
      $quote,
      other_ofr
    );

    uint ofr = mgv.newOffer($base, $quote, 1 ether, 1 ether, 190_000, 0, 0);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    require(mgv.best($base, $quote) == 0, "snipe in posthook must work");
  }

  function test_newOffer_on_closed_fails() public {
    mgv.kill();
    try mgv.newOffer($base, $quote, 1 ether, 1 ether, 0, 0, 0) {
      fail("newOffer should fail on closed market");
    } catch Error(string memory r) {
      revertEq(r, "mgv/dead");
    }
  }

  /* # Mangrove closed/inactive */

  function test_take_on_closed_fails() public {
    uint ofr = mgv.newOffer($base, $quote, 1 ether, 1 ether, 0, 0, 0);

    mgv.kill();
    try tkr.take(ofr, 1 ether) {
      fail("take offer should fail on closed market");
    } catch Error(string memory r) {
      revertEq(r, "mgv/dead");
    }
  }

  function test_newOffer_on_inactive_fails() public {
    mgv.deactivate($base, $quote);
    try mgv.newOffer($base, $quote, 1 ether, 1 ether, 0, 0, 0) {
      fail("newOffer should fail on closed market");
    } catch Error(string memory r) {
      revertEq(r, "mgv/inactive");
    }
  }

  function test_receive_on_closed_fails() public {
    mgv.kill();

    (bool success, bytes memory retdata) = $mgv.call{value: 10 ether}("");
    if (success) {
      fail("receive() should fail on closed market");
    } else {
      string memory r = getReason(retdata);
      revertEq(r, "mgv/dead");
    }
  }

  function test_marketOrder_on_closed_fails() public {
    mgv.kill();
    try tkr.marketOrder(1 ether, 1 ether) {
      fail("marketOrder should fail on closed market");
    } catch Error(string memory r) {
      revertEq(r, "mgv/dead");
    }
  }

  function test_snipe_on_closed_fails() public {
    mgv.kill();
    try tkr.take(0, 1 ether) {
      fail("snipe should fail on closed market");
    } catch Error(string memory r) {
      revertEq(r, "mgv/dead");
    }
  }

  function test_withdraw_on_closed_ok() public {
    mgv.kill();
    mgv.withdraw(0.1 ether);
  }

  function test_retractOffer_on_closed_ok() public {
    uint ofr = mgv.newOffer($base, $quote, 1 ether, 1 ether, 0, 0, 0);
    mgv.kill();
    mgv.retractOffer($base, $quote, ofr, false);
  }

  function test_updateOffer_on_closed_fails() public {
    uint ofr = mgv.newOffer($base, $quote, 1 ether, 1 ether, 0, 0, 0);
    mgv.kill();
    try mgv.updateOffer($base, $quote, 1 ether, 1 ether, 0, 0, 0, ofr) {
      fail("update offer should fail on closed market");
    } catch Error(string memory r) {
      revertEq(r, "mgv/dead");
    }
  }

  function test_activation_emits_events_in_order() public {
    expectFrom($mgv);
    emit SetActive($quote, $base, true);
    expectFrom($mgv);
    emit SetFee($quote, $base, 7);
    expectFrom($mgv);
    emit SetDensity($quote, $base, 0);
    expectFrom($mgv);
    emit SetGasbase($quote, $base, 3);
    mgv.activate($quote, $base, 7, 0, 3);
  }

  function test_updateOffer_on_inactive_fails() public {
    uint ofr = mgv.newOffer($base, $quote, 1 ether, 1 ether, 0, 0, 0);
    expectFrom($mgv);
    emit SetActive($base, $quote, false);
    mgv.deactivate($base, $quote);
    try mgv.updateOffer($base, $quote, 1 ether, 1 ether, 0, 0, 0, ofr) {
      fail("update offer should fail on inactive market");
    } catch Error(string memory r) {
      revertEq(r, "mgv/inactive");
    }
  }
}
