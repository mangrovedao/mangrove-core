// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {console} from "@mgv/test/lib/MangroveTest.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {OLKey} from "@mgv/src/core/MgvLib.sol";
import {MIDDLE_BIN, ROOT_HIGHER_BIN} from "@mgv/test/lib/gas/GasTestBase.t.sol";
import {OfferPosthookFailGasDeltaTest} from "./OfferPosthookFailGasDelta.t.sol";
import {OfferGasReqBaseTest} from "@mgv/test/lib/gas/OfferGasReqBase.t.sol";

///@notice base class for measuring gasbase for a pair.
abstract contract OfferGasBaseBaseTest is OfferGasReqBaseTest {
  OfferPosthookFailGasDeltaTest internal gasDeltaTest;
  uint internal offerGivesOl;
  uint internal offerGivesLo;
  uint internal immutable MIN_GASREQ = 3;

  function setUpOptions() internal virtual override {
    super.setUpOptions();
    options.measureGasusedMangrove = false;
  }

  function setUpOfferGasBaseBaseTest() internal virtual {
    gasDeltaTest = new OfferPosthookFailGasDeltaTest();
    gasDeltaTest.setUpGasTest(options);
    description = string.concat(description, " - Offer gasbase");
  }

  function setUpGeneric() public virtual override {
    super.setUpGeneric();
    setUpOfferGasBaseBaseTest();
  }

  function setUpPolygon() public virtual override {
    super.setUpPolygon();
    setUpOfferGasBaseBaseTest();
  }

  function setUpTokens(string memory baseToken, string memory quoteToken) public virtual override {
    super.setUpTokens(baseToken, quoteToken);

    gasDeltaTest.setUpTokens(base, quote);

    // Create naked offers with 0 gasreq
    address makerBase = freshAddress("makerBase");
    address makerQuote = freshAddress("makerQuote");
    deal($(base), makerBase, 200000 ether);
    deal($(quote), makerQuote, 200000 ether);
    deal(makerBase, 1000 ether);
    deal(makerQuote, 1000 ether);
    // Make offers 2 times minimum, but only approve minimum, thus allow for failure to deliver
    offerGivesOl = 2 * reader.minVolume(olKey, MIN_GASREQ);
    offerGivesLo = 2 * reader.minVolume(lo, MIN_GASREQ);

    vm.prank(makerBase);
    mgv.fund{value: 10 ether}();
    vm.prank(makerQuote);
    mgv.fund{value: 10 ether}();
    vm.prank(makerBase);
    TransferLib.approveToken(base, $(mgv), offerGivesOl / 2);
    vm.prank(makerQuote);
    TransferLib.approveToken(quote, $(mgv), offerGivesLo / 2);
    vm.prank(makerBase);
    mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), offerGivesOl, MIN_GASREQ, 0);
    vm.prank(makerBase);
    mgv.newOfferByTick(olKey, olKey.tick(ROOT_HIGHER_BIN), offerGivesOl, MIN_GASREQ, 0);
    vm.prank(makerQuote);
    mgv.newOfferByTick(lo, lo.tick(MIDDLE_BIN), offerGivesLo, MIN_GASREQ, 0);
    vm.prank(makerQuote);
    mgv.newOfferByTick(lo, lo.tick(ROOT_HIGHER_BIN), offerGivesLo, MIN_GASREQ, 0);
  }

  ///@notice expected worst case gasbase - having to update structures for a more expensive offer, emptying bin, cold transfers, 0 amount in receiving wallets.
  function gasbase_to_empty_bin(OLKey memory _olKey, bool failure) internal {
    uint volume = failure ? type(uint96).max : 1;
    (IMangrove _mgv,,,) = getStored();
    prankTaker(_olKey);
    _gas();
    (uint takerGot,,, uint fee) = _mgv.marketOrderByTick(_olKey, _olKey.tick(MIDDLE_BIN), volume, true);
    gas_();

    assertEq(takerGot + fee == 0, failure, "taker should get some of the offer if not failure");
    assertNotEq(mgv.best(_olKey), 0, "more expensive offer should be left behind");
    if (options.measureGasusedMangrove) {
      // It is ~3000 without optimizations for a minimum gasreq offer
      assertGt(getMeasuredGasused(0), 0, "gasused should be measured");
    }
  }

  function test_gasbase_to_empty_bin_base_quote_success() public {
    gasbase_to_empty_bin(olKey, false);
    printDescription(" - Case: base/quote gasbase for taking single offer to empty bin (success)");
  }

  function test_gasbase_to_empty_bin_base_quote_failure() public {
    gasbase_to_empty_bin(olKey, true);
    printDescription(" - Case: base/quote gasbase for taking single offer to empty bin (failure)");
  }

  function test_gasbase_to_empty_bin_quote_base_success() public {
    gasbase_to_empty_bin(lo, false);
    printDescription(" - Case: quote/base gasbase for taking single offer to empty bin (success)");
  }

  function test_gasbase_to_empty_bin_quote_base_failure() public {
    gasbase_to_empty_bin(lo, true);
    printDescription(" - Case: quote/base gasbase for taking single offer to empty bin (failure)");
  }

  function test_posthook_fail_delta_deep_order_base_quote() public {
    gasDeltaTest.posthook_delta_deep_order(olKey);
    printDescription(
      " - Case: quote/base posthook fail with failing posthook (worst case) delta for taking deep order - cost for 1 successful and 19 failing offers"
    );
  }

  function test_posthook_fail_delta_deep_order_quote_base() public {
    gasDeltaTest.posthook_delta_deep_order(lo);
    printDescription(
      " - Case: quote/base posthook fail with failing posthook (worst case) delta for taking deep order - cost for 1 successful and 19 failing offers"
    );
  }

  function test_gasbase_transfers_estimate() public {
    uint outbound_gas = measureTransferGas($(base));
    uint inbound_gas = measureTransferGas($(quote));
    uint gasbase = 2 * (outbound_gas + inbound_gas);
    console.log("Gas used: %s", gasbase);
    printDescription(" - Case: ActivateSemibook transfers estimate");
  }
}
