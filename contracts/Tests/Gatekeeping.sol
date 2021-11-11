// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../AbstractMangrove.sol";
import "../MgvLib.sol";
import {MgvPack as MP} from "../MgvPack.sol";
import "hardhat/console.sol";
import "@giry/hardhat-test-solidity/test.sol";

import "./Toolbox/TestUtils.sol";

import "./Agents/TestToken.sol";
import "./Agents/TestMaker.sol";
import "./Agents/TestMoriartyMaker.sol";
import "./Agents/MakerDeployer.sol";
import "./Agents/TestTaker.sol";

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
    uint overhead_gasbase,
    uint offer_gasbase
  ) public {
    mgv.activate(base, quote, fee, density, overhead_gasbase, offer_gasbase);
  }

  function setGasbase(
    address base,
    address quote,
    uint overhead_gasbase,
    uint offer_gasbase
  ) public {
    mgv.setGasbase(base, quote, overhead_gasbase, offer_gasbase);
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

contract Deployer {
  AbstractMangrove mgv;

  function deploy() public returns (AbstractMangrove) {
    mgv = MgvSetup.deploy(msg.sender);
    return mgv;
  }

  function setGovernance(address governance) public {
    mgv.setGovernance(governance);
  }
}

// In these tests, the testing contract is the market maker.
contract Gatekeeping_Test is IMaker, HasMgvEvents {
  receive() external payable {}

  AbstractMangrove mgv;
  TestTaker tkr;
  TestMaker mkr;
  TestMaker dual_mkr;
  address base;
  address quote;

  function gov_is_not_sender_test() public {
    Deployer deployer = new Deployer();
    AbstractMangrove _mgv = deployer.deploy();

    TestEvents.eq(
      _mgv.governance(),
      address(this),
      "governance should return this"
    );
  }

  function a_beforeAll() public {
    TestToken baseT = TokenSetup.setup("A", "$A");
    TestToken quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    mgv = MgvSetup.setup(baseT, quoteT);
    tkr = TakerSetup.setup(mgv, base, quote);
    mkr = MakerSetup.setup(mgv, base, quote);
    dual_mkr = MakerSetup.setup(mgv, quote, base);

    address(tkr).transfer(10 ether);
    address(mkr).transfer(10 ether);
    address(dual_mkr).transfer(10 ether);

    bool noRevert;
    (noRevert, ) = address(mgv).call{value: 10 ether}("");

    mkr.provisionMgv(5 ether);
    dual_mkr.provisionMgv(5 ether);

    baseT.mint(address(this), 2 ether);
    quoteT.mint(address(tkr), 1 ether);
    quoteT.mint(address(mkr), 1 ether);
    baseT.mint(address(dual_mkr), 1 ether);

    baseT.approve(address(mgv), 1 ether);
    quoteT.approve(address(mgv), 1 ether);
    tkr.approveMgv(quoteT, 1 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Gatekeeping_Test/maker");
    Display.register(base, "$A");
    Display.register(quote, "$B");
    Display.register(address(mgv), "mgv");
    Display.register(address(tkr), "taker[$A,$B]");
    Display.register(address(dual_mkr), "maker[$B,$A]");
    Display.register(address(mkr), "maker[$A,$B]");
  }

  /* # Test Config */

  function gov_can_transfer_rights_test() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    mgv.setGovernance(address(notAdmin));

    try mgv.setFee(base, quote, 0) {
      TestEvents.fail("testing contracts should no longer be admin");
    } catch {}

    try notAdmin.setFee(base, quote, 1) {} catch {
      TestEvents.fail("notAdmin should have been given admin rights");
    }
    // Logging tests
    TestEvents.expectFrom(address(mgv));
    emit SetGovernance(address(notAdmin));
    emit SetFee(base, quote, 1);
  }

  function only_gov_can_set_fee_test() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    try notAdmin.setFee(base, quote, 0) {
      TestEvents.fail("nonadmin cannot set fee");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/unauthorized");
    }
  }

  function only_gov_can_set_density_test() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    try notAdmin.setDensity(base, quote, 0) {
      TestEvents.fail("nonadmin cannot set density");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/unauthorized");
    }
  }

  function set_zero_density_test() public {
    try mgv.setDensity(base, quote, 0) {} catch Error(string memory) {
      TestEvents.fail("setting density to 0 should work");
    }
    // Logging tests
    TestEvents.expectFrom(address(mgv));
    emit SetDensity(base, quote, 0);
  }

  function only_gov_can_kill_test() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    try notAdmin.kill() {
      TestEvents.fail("nonadmin cannot kill");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/unauthorized");
    }
  }

  function killing_updates_config_test() public {
    (bytes32 global, ) = mgv.config(address(0), address(0));
    TestEvents.check(
      MP.global_unpack_dead(global) == 0,
      "mgv should not be dead "
    );
    mgv.kill();
    (global, ) = mgv.config(address(0), address(0));
    TestEvents.check(MP.global_unpack_dead(global) > 0, "mgv should be dead ");
    // Logging tests
    TestEvents.expectFrom(address(mgv));
    emit Kill();
  }

  function kill_is_idempotent_test() public {
    (bytes32 global, ) = mgv.config(address(0), address(0));
    TestEvents.check(
      MP.global_unpack_dead(global) == 0,
      "mgv should not be dead "
    );
    mgv.kill();
    (global, ) = mgv.config(address(0), address(0));
    TestEvents.check(MP.global_unpack_dead(global) > 0, "mgv should be dead");
    mgv.kill();
    (global, ) = mgv.config(address(0), address(0));
    TestEvents.check(
      MP.global_unpack_dead(global) > 0,
      "mgv should still be dead"
    );
    // Logging tests
    TestEvents.expectFrom(address(mgv));
    emit Kill();
    emit Kill();
  }

  function only_gov_can_set_vault_test() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    try notAdmin.setVault(address(this)) {
      TestEvents.fail("nonadmin cannot set vault");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/unauthorized");
    }
  }

  function only_gov_can_set_monitor_test() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    try notAdmin.setMonitor(address(this)) {
      TestEvents.fail("nonadmin cannot set monitor");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/unauthorized");
    }
  }

  function only_gov_can_set_active_test() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    try notAdmin.activate(quote, base, 0, 100, 30_000, 0) {
      TestEvents.fail("nonadmin cannot set active");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/unauthorized");
    }
  }

  function only_gov_can_set_gasprice_test() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    try notAdmin.setGasprice(0) {
      TestEvents.fail("nonadmin cannot set gasprice");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/unauthorized");
    }
  }

  function only_gov_can_set_gasmax_test() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    try notAdmin.setGasmax(0) {
      TestEvents.fail("nonadmin cannot set gasmax");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/unauthorized");
    }
  }

  function only_gov_can_set_gasbase_test() public {
    NotAdmin notAdmin = new NotAdmin(mgv);
    try notAdmin.setGasbase(base, quote, 0, 0) {
      TestEvents.fail("nonadmin cannot set gasbase");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/unauthorized");
    }
  }

  function empty_mgv_ok_test() public {
    try tkr.marketOrder(0, 0) {} catch {
      TestEvents.fail("market order on empty mgv should not fail");
    }
    // Logging tests
  }

  function set_fee_ceiling_test() public {
    try mgv.setFee(base, quote, 501) {} catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/config/fee/<=500");
    }
  }

  function set_density_ceiling_test() public {
    try mgv.setDensity(base, quote, uint(type(uint32).max) + 1) {
      TestEvents.fail("density above ceiling should fail");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/config/density/32bits");
    }
  }

  function set_gasprice_ceiling_test() public {
    try mgv.setGasprice(uint(type(uint16).max) + 1) {
      TestEvents.fail("gasprice above ceiling should fail");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/config/gasprice/16bits");
    }
  }

  function set_zero_gasbase_test() public {
    try mgv.setGasbase(base, quote, 0, 0) {} catch Error(string memory) {
      TestEvents.fail("setting gasbases to 0 should work");
    }
  }

  function set_gasbase_ceiling_test() public {
    try mgv.setGasbase(base, quote, uint(type(uint24).max) + 1, 0) {
      TestEvents.fail("overhead_gasbase above ceiling should fail");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/config/overhead_gasbase/24bits");
    }

    try mgv.setGasbase(base, quote, 0, uint(type(uint24).max) + 1) {
      TestEvents.fail("offer_gasbase above ceiling should fail");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/config/offer_gasbase/24bits");
    }
  }

  function set_gasmax_ceiling_test() public {
    try mgv.setGasmax(uint(type(uint24).max) + 1) {
      TestEvents.fail("gasmax above ceiling should fail");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/config/gasmax/24bits");
    }
  }

  function makerWants_wider_than_96_bits_fails_newOffer_test() public {
    try mkr.newOffer(2**96, 1 ether, 10_000, 0) {
      TestEvents.fail("Too wide offer should not be inserted");
    } catch Error(string memory r) {
      TestEvents.eq(r, "mgv/writeOffer/wants/96bits", "wrong revert reason");
    }
  }

  function retractOffer_wrong_owner_fails_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 10_000, 0);
    try mgv.retractOffer(base, quote, ofr, false) {
      TestEvents.fail("Too wide offer should not be inserted");
    } catch Error(string memory r) {
      TestEvents.eq(r, "mgv/retractOffer/unauthorized", "wrong revert reason");
    }
  }

  function makerGives_wider_than_96_bits_fails_newOffer_test() public {
    try mkr.newOffer(1, 2**96, 10_000, 0) {
      TestEvents.fail("Too wide offer should not be inserted");
    } catch Error(string memory r) {
      TestEvents.eq(r, "mgv/writeOffer/gives/96bits", "wrong revert reason");
    }
  }

  function makerGasreq_wider_than_24_bits_fails_newOffer_test() public {
    try mkr.newOffer(1, 1, 2**24, 0) {
      TestEvents.fail("Too wide offer should not be inserted");
    } catch Error(string memory r) {
      TestEvents.eq(r, "mgv/writeOffer/gasreq/tooHigh", "wrong revert reason");
    }
  }

  function makerGasreq_bigger_than_gasmax_fails_newOffer_test() public {
    (bytes32 cfg, ) = mgv.config(base, quote);
    try mkr.newOffer(1, 1, MP.global_unpack_gasmax(cfg) + 1, 0) {
      TestEvents.fail("Offer should not be inserted");
    } catch Error(string memory r) {
      TestEvents.eq(r, "mgv/writeOffer/gasreq/tooHigh", "wrong revert reason");
    }
  }

  function makerGasreq_at_gasmax_succeeds_newOffer_test() public {
    (bytes32 cfg, ) = mgv.config(base, quote);
    try
      mkr.newOffer(1 ether, 1 ether, MP.global_unpack_gasmax(cfg), 0)
    returns (uint ofr) {
      TestEvents.check(
        mgv.isLive(mgv.offers(base, quote, ofr)),
        "Offer should have been inserted"
      );
      // Logging tests
      TestEvents.expectFrom(address(mgv));
      emit OfferWrite(
        address(base),
        address(quote),
        address(mkr),
        1 ether, //base
        1 ether, //quote
        MP.global_unpack_gasprice(cfg), //gasprice
        MP.global_unpack_gasmax(cfg), //gasreq
        ofr, //ofrId
        0 // prev
      );
      emit Debit(
        address(mkr),
        TestUtils.getProvision(
          mgv,
          address(base),
          address(quote),
          MP.global_unpack_gasmax(cfg),
          0
        )
      );
    } catch {
      TestEvents.fail("Offer at gasmax should pass");
    }
  }

  function makerGasreq_lower_than_density_fails_newOffer_test() public {
    (, bytes32 cfg) = mgv.config(base, quote);
    uint amount = (1 + MP.local_unpack_offer_gasbase(cfg)) *
      MP.local_unpack_density(cfg);
    try mkr.newOffer(amount - 1, amount - 1, 1, 0) {
      TestEvents.fail("Offer should not be inserted");
    } catch Error(string memory r) {
      TestEvents.eq(r, "mgv/writeOffer/density/tooLow", "wrong revert reason");
    }
  }

  function makerGasreq_at_density_suceeds_test() public {
    (bytes32 glob, bytes32 cfg) = mgv.config(base, quote);
    uint amount = (1 + MP.local_unpack_offer_gasbase(cfg)) *
      MP.local_unpack_density(cfg);
    try mkr.newOffer(amount, amount, 1, 0) returns (uint ofr) {
      TestEvents.check(
        mgv.isLive(mgv.offers(base, quote, ofr)),
        "Offer should have been inserted"
      );
      // Logging tests
      TestEvents.expectFrom(address(mgv));
      emit OfferWrite(
        address(base),
        address(quote),
        address(mkr),
        amount, //base
        amount, //quote
        MP.global_unpack_gasprice(glob), //gasprice
        1, //gasreq
        ofr, //ofrId
        0 // prev
      );
      emit Debit(
        address(mkr),
        TestUtils.getProvision(mgv, address(base), address(quote), 1, 0)
      );
    } catch {
      TestEvents.fail("Offer at density should pass");
    }
  }

  function makerGasprice_wider_than_16_bits_fails_newOffer_test() public {
    try mkr.newOffer(1, 1, 1, 2**16, 0) {
      TestEvents.fail("Too wide offer should not be inserted");
    } catch Error(string memory r) {
      TestEvents.eq(r, "mgv/writeOffer/gasprice/16bits", "wrong revert reason");
    }
  }

  function takerWants_wider_than_160_bits_fails_marketOrder_test() public {
    try tkr.marketOrder(2**160, 0) {
      TestEvents.fail("takerWants > 160bits, order should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "mgv/mOrder/takerWants/160bits", "wrong revert reason");
    }
  }

  function takerWants_above_96bits_fails_snipes_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [
      ofr,
      uint(type(uint96).max) + 1,
      type(uint96).max,
      type(uint).max
    ];
    try mgv.snipes(base, quote, targets, true) {
      TestEvents.fail("Snipes with takerWants > 96bits should fail");
    } catch Error(string memory reason) {
      TestUtils.revertEq(reason, "mgv/snipes/takerWants/96bits");
    }
  }

  function takerGives_above_96bits_fails_snipes_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [
      ofr,
      type(uint96).max,
      uint(type(uint96).max) + 1,
      type(uint).max
    ];
    try mgv.snipes(base, quote, targets, true) {
      TestEvents.fail("Snipes with takerGives > 96bits should fail");
    } catch Error(string memory reason) {
      TestUtils.revertEq(reason, "mgv/snipes/takerGives/96bits");
    }
  }

  function initial_allowance_is_zero_test() public {
    TestEvents.eq(
      mgv.allowances(base, quote, address(tkr), address(this)),
      0,
      "initial allowance should be 0"
    );
  }

  function cannot_snipesFor_for_without_allowance_test() public {
    TestToken(base).mint(address(mkr), 1 ether);
    mkr.approveMgv(TestToken(base), 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 300_000];
    try mgv.snipesFor(base, quote, targets, true, address(tkr)) {
      TestEvents.fail("snipeFor should fail without allowance");
    } catch Error(string memory reason) {
      TestUtils.revertEq(reason, "mgv/lowAllowance");
    }
  }

  function cannot_marketOrderFor_for_without_allowance_test() public {
    TestToken(base).mint(address(mkr), 1 ether);
    mkr.approveMgv(TestToken(base), 1 ether);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    try mgv.marketOrderFor(base, quote, 1 ether, 1 ether, true, address(tkr)) {
      TestEvents.fail("marketOrderfor should fail without allowance");
    } catch Error(string memory reason) {
      TestUtils.revertEq(reason, "mgv/lowAllowance");
    }
  }

  function can_marketOrderFor_for_with_allowance_test() public {
    TestToken(base).mint(address(mkr), 1 ether);
    mkr.approveMgv(TestToken(base), 1 ether);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    tkr.approveSpender(address(this), 1.2 ether);
    (uint takerGot, ) = mgv.marketOrderFor(
      base,
      quote,
      1 ether,
      1 ether,
      true,
      address(tkr)
    );
    TestEvents.eq(
      mgv.allowances(base, quote, address(tkr), address(this)),
      0.2 ether,
      "allowance should have correctly reduced"
    );
  }

  /* # Internal IMaker setup */

  bytes trade_cb;
  bytes posthook_cb;

  // maker's trade fn for the mgv
  function makerExecute(ML.SingleOrder calldata)
    external
    override
    returns (bytes32 ret)
  {
    ret; // silence unused function parameter
    bool success;
    if (trade_cb.length > 0) {
      (success, ) = address(this).call(trade_cb);
      require(success, "makerExecute callback must work");
    }
    return "";
  }

  function makerPosthook(
    ML.SingleOrder calldata order,
    ML.OrderResult calldata result
  ) external override {
    bool success;
    order; // silence compiler warning
    if (posthook_cb.length > 0) {
      (success, ) = address(this).call(posthook_cb);
      bool tradeResult = (result.mgvData == "mgv/tradeSuccess");
      require(success == tradeResult, "makerPosthook callback must work");
    }
  }

  /* # Reentrancy */

  /* New Offer failure */

  function newOfferKO() external {
    try mgv.newOffer(base, quote, 1 ether, 1 ether, 30_000, 0, 0) {
      TestEvents.fail("newOffer on same pair should fail");
    } catch Error(string memory reason) {
      TestUtils.revertEq(reason, "mgv/reentrancyLocked");
    }
  }

  function newOffer_on_reentrancy_fails_test() public {
    uint ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0, 0);
    trade_cb = abi.encodeWithSelector(this.newOfferKO.selector);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
  }

  /* New Offer success */

  // ! may be called with inverted _base and _quote
  function newOfferOK(address _base, address _quote) external {
    mgv.newOffer(_base, _quote, 1 ether, 1 ether, 30_000, 0, 0);
  }

  function newOffer_on_reentrancy_succeeds_test() public {
    uint ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 200_000, 0, 0);
    trade_cb = abi.encodeWithSelector(this.newOfferOK.selector, quote, base);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    require(mgv.best(quote, base) == 1, "newOffer on swapped pair must work");
  }

  function newOffer_on_posthook_succeeds_test() public {
    uint ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 200_000, 0, 0);
    posthook_cb = abi.encodeWithSelector(this.newOfferOK.selector, base, quote);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    require(mgv.best(base, quote) == 2, "newOffer on posthook must work");
  }

  /* Update offer failure */

  function updateOfferKO(uint ofr) external {
    try mgv.updateOffer(base, quote, 1 ether, 2 ether, 35_000, 0, 0, ofr) {
      TestEvents.fail("update offer on same pair should fail");
    } catch Error(string memory reason) {
      TestUtils.revertEq(reason, "mgv/reentrancyLocked");
    }
  }

  function updateOffer_on_reentrancy_fails_test() public {
    uint ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0, 0);
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

  function updateOffer_on_reentrancy_succeeds_test() public {
    uint other_ofr = mgv.newOffer(quote, base, 1 ether, 1 ether, 100_000, 0, 0);

    trade_cb = abi.encodeWithSelector(
      this.updateOfferOK.selector,
      quote,
      base,
      other_ofr
    );
    uint ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 400_000, 0, 0);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    (, ML.OfferDetail memory od) = mgv.offerInfo(quote, base, other_ofr);
    require(od.gasreq == 35_000, "updateOffer on swapped pair must work");
  }

  function updateOffer_on_posthook_succeeds_test() public {
    uint other_ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0, 0);
    posthook_cb = abi.encodeWithSelector(
      this.updateOfferOK.selector,
      base,
      quote,
      other_ofr
    );
    uint ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 300_000, 0, 0);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    (, ML.OfferDetail memory od) = mgv.offerInfo(base, quote, other_ofr);
    require(od.gasreq == 35_000, "updateOffer on posthook must work");
  }

  /* Cancel Offer failure */

  function retractOfferKO(uint id) external {
    try mgv.retractOffer(base, quote, id, false) {
      TestEvents.fail("retractOffer on same pair should fail");
    } catch Error(string memory reason) {
      TestUtils.revertEq(reason, "mgv/reentrancyLocked");
    }
  }

  function retractOffer_on_reentrancy_fails_test() public {
    uint ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0, 0);
    trade_cb = abi.encodeWithSelector(this.retractOfferKO.selector, ofr);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
  }

  /* Cancel Offer success */

  function retractOfferOK(
    address _base,
    address _quote,
    uint id
  ) external {
    mgv.retractOffer(_base, _quote, id, false);
  }

  function retractOffer_on_reentrancy_succeeds_test() public {
    uint other_ofr = mgv.newOffer(quote, base, 1 ether, 1 ether, 90_000, 0, 0);
    trade_cb = abi.encodeWithSelector(
      this.retractOfferOK.selector,
      quote,
      base,
      other_ofr
    );

    uint ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 90_000, 0, 0);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    require(
      mgv.best(quote, base) == 0,
      "retractOffer on swapped pair must work"
    );
  }

  function retractOffer_on_posthook_succeeds_test() public {
    uint other_ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 190_000, 0, 0);
    posthook_cb = abi.encodeWithSelector(
      this.retractOfferOK.selector,
      base,
      quote,
      other_ofr
    );

    uint ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 90_000, 0, 0);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    require(mgv.best(base, quote) == 0, "retractOffer on posthook must work");
  }

  /* Market Order failure */

  function marketOrderKO() external {
    try mgv.marketOrder(base, quote, 0.2 ether, 0.2 ether, true) {
      TestEvents.fail("marketOrder on same pair should fail");
    } catch Error(string memory reason) {
      TestUtils.revertEq(reason, "mgv/reentrancyLocked");
    }
  }

  function marketOrder_on_reentrancy_fails_test() public {
    uint ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 100_000, 0, 0);
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

  function marketOrder_on_reentrancy_succeeds_test() public {
    console.log(
      "dual mkr offer",
      dual_mkr.newOffer(0.5 ether, 0.5 ether, 30_000, 0)
    );
    uint ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 392_000, 0, 0);
    console.log("normal offer", ofr);
    trade_cb = abi.encodeWithSelector(this.marketOrderOK.selector, quote, base);
    require(tkr.take(ofr, 0.1 ether), "take must succeed or test is void");
    require(
      mgv.best(quote, base) == 0,
      "2nd market order must have emptied mgv"
    );
  }

  function marketOrder_on_posthook_succeeds_test() public {
    uint ofr = mgv.newOffer(base, quote, 0.5 ether, 0.5 ether, 500_000, 0, 0);
    mgv.newOffer(base, quote, 0.5 ether, 0.5 ether, 200_000, 0, 0);
    posthook_cb = abi.encodeWithSelector(
      this.marketOrderOK.selector,
      base,
      quote
    );
    require(tkr.take(ofr, 0.6 ether), "take must succeed or test is void");
    require(
      mgv.best(base, quote) == 0,
      "2nd market order must have emptied mgv"
    );
  }

  /* Snipe failure */

  function snipesKO(uint id) external {
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [id, 1 ether, type(uint96).max, type(uint48).max];
    try mgv.snipes(base, quote, targets, true) {
      TestEvents.fail("snipe on same pair should fail");
    } catch Error(string memory reason) {
      TestUtils.revertEq(reason, "mgv/reentrancyLocked");
    }
  }

  function snipe_on_reentrancy_fails_test() public {
    uint ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 60_000, 0, 0);
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

  function snipes_on_reentrancy_succeeds_test() public {
    uint other_ofr = dual_mkr.newOffer(1 ether, 1 ether, 30_000, 0);
    trade_cb = abi.encodeWithSelector(
      this.snipesOK.selector,
      quote,
      base,
      other_ofr
    );

    uint ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 190_000, 0, 0);
    require(tkr.take(ofr, 0.1 ether), "take must succeed or test is void");
    require(mgv.best(quote, base) == 0, "snipe in swapped pair must work");
  }

  function snipes_on_posthook_succeeds_test() public {
    uint other_ofr = mkr.newOffer(1 ether, 1 ether, 30_000, 0);
    posthook_cb = abi.encodeWithSelector(
      this.snipesOK.selector,
      base,
      quote,
      other_ofr
    );

    uint ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 190_000, 0, 0);
    require(tkr.take(ofr, 1 ether), "take must succeed or test is void");
    require(mgv.best(base, quote) == 0, "snipe in posthook must work");
  }

  function newOffer_on_closed_fails_test() public {
    mgv.kill();
    try mgv.newOffer(base, quote, 1 ether, 1 ether, 0, 0, 0) {
      TestEvents.fail("newOffer should fail on closed market");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/dead");
    }
  }

  /* # Mangrove closed/inactive */

  function take_on_closed_fails_test() public {
    uint ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 0, 0, 0);

    mgv.kill();
    try tkr.take(ofr, 1 ether) {
      TestEvents.fail("take offer should fail on closed market");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/dead");
    }
  }

  function newOffer_on_inactive_fails_test() public {
    mgv.deactivate(base, quote);
    try mgv.newOffer(base, quote, 1 ether, 1 ether, 0, 0, 0) {
      TestEvents.fail("newOffer should fail on closed market");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/inactive");
    }
  }

  function receive_on_closed_fails_test() public {
    mgv.kill();

    (bool success, bytes memory retdata) = address(mgv).call{value: 10 ether}(
      ""
    );
    if (success) {
      TestEvents.fail("receive() should fail on closed market");
    } else {
      string memory r = TestUtils.getReason(retdata);
      TestUtils.revertEq(r, "mgv/dead");
    }
  }

  function marketOrder_on_closed_fails_test() public {
    mgv.kill();
    try tkr.marketOrder(1 ether, 1 ether) {
      TestEvents.fail("marketOrder should fail on closed market");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/dead");
    }
  }

  function snipe_on_closed_fails_test() public {
    mgv.kill();
    try tkr.take(0, 1 ether) {
      TestEvents.fail("snipe should fail on closed market");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/dead");
    }
  }

  function withdraw_on_closed_ok_test() public {
    mgv.kill();
    mgv.withdraw(0.1 ether);
  }

  function retractOffer_on_closed_ok_test() public {
    uint ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 0, 0, 0);
    mgv.kill();
    mgv.retractOffer(base, quote, ofr, false);
  }

  function updateOffer_on_closed_fails_test() public {
    uint ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 0, 0, 0);
    mgv.kill();
    try mgv.updateOffer(base, quote, 1 ether, 1 ether, 0, 0, 0, ofr) {
      TestEvents.fail("update offer should fail on closed market");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/dead");
    }
  }

  function activation_emits_events_in_order_test() public {
    mgv.activate(quote, base, 7, 0, 1, 3);
    TestEvents.expectFrom(address(mgv));
    emit SetActive(quote, base, true);
    emit SetFee(quote, base, 7);
    emit SetDensity(quote, base, 0);
    emit SetGasbase(quote, base, 1, 3);
  }

  function updateOffer_on_inactive_fails_test() public {
    uint ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, 0, 0, 0);
    mgv.deactivate(base, quote);
    try mgv.updateOffer(base, quote, 1 ether, 1 ether, 0, 0, 0, ofr) {
      TestEvents.fail("update offer should fail on inactive market");
    } catch Error(string memory r) {
      TestUtils.revertEq(r, "mgv/inactive");
      TestEvents.expectFrom(address(mgv));
      emit SetActive(base, quote, false);
    }
  }
}
