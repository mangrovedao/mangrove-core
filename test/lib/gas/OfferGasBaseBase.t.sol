// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {console} from "mgv_test/lib/MangroveTest.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {TransferLib} from "mgv_lib/TransferLib.sol";
import {OLKey} from "mgv_src/core/MgvLib.sol";
import {MIDDLE_BIN} from "mgv_test/lib/gas/GasTestBase.t.sol";
import {OfferPosthookFailGasDeltaTest} from "./OfferPosthookFailGasDelta.t.sol";
import {OfferGasReqBaseTest} from "mgv_test/lib/gas/OfferGasReqBase.t.sol";

///@notice base class for measuring gasbase for a pair.
abstract contract OfferGasBaseBaseTest is OfferGasReqBaseTest {
  OfferPosthookFailGasDeltaTest internal gasDeltaTest;
  uint internal offerGivesOl;
  uint internal offerGivesLo;

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
    offerGivesOl = 2 * reader.minVolume(olKey, 100000);
    offerGivesLo = 2 * reader.minVolume(lo, 100000);

    vm.prank(makerBase);
    mgv.fund{value: 10 ether}();
    vm.prank(makerQuote);
    mgv.fund{value: 10 ether}();
    vm.prank(makerBase);
    TransferLib.approveToken(base, $(mgv), offerGivesOl / 2);
    vm.prank(makerQuote);
    TransferLib.approveToken(quote, $(mgv), offerGivesLo / 2);
    vm.prank(makerBase);
    mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), offerGivesOl, 100000, 0);
    vm.prank(makerQuote);
    mgv.newOfferByTick(lo, lo.tick(MIDDLE_BIN), offerGivesLo, 100000, 0);
  }

  function gasbase_to_empty_book(OLKey memory _olKey, bool failure) internal {
    uint volume = failure ? type(uint96).max : 1;
    (IMangrove _mgv,,,) = getStored();
    prankTaker(_olKey);
    _gas();
    (uint takerGot,,, uint fee) = _mgv.marketOrderByTick(_olKey, _olKey.tick(MIDDLE_BIN), volume, true);
    gas_();

    assertEq(takerGot + fee == 0, failure, "taker should get some of the offer if not failure");
    assertEq(mgv.best(_olKey), 0, "book should be empty");
  }

  function test_gasbase_to_empty_book_base_quote_success() public {
    gasbase_to_empty_book(olKey, false);
    description =
      string.concat(description, " - Case: base/quote gasbase for taking single offer to empty book (success)");
    printDescription();
  }

  function test_gasbase_to_empty_book_base_quote_failure() public {
    gasbase_to_empty_book(olKey, true);
    description =
      string.concat(description, " - Case: base/quote gasbase for taking single offer to empty book (failure)");
    printDescription();
  }

  function test_gasbase_to_empty_book_quote_base_success() public {
    gasbase_to_empty_book(lo, false);
    description =
      string.concat(description, " - Case: quote/base gasbase for taking single offer to empty book (success)");
    printDescription();
  }

  function test_gasbase_to_empty_book_quote_base_failure() public {
    gasbase_to_empty_book(lo, true);
    description =
      string.concat(description, " - Case: quote/base gasbase for taking single offer to empty book (failure)");
    printDescription();
  }

  function test_posthook_fail_delta_deep_order_base_quote() public {
    gasDeltaTest.posthook_delta_deep_order(olKey);
    description = string.concat(
      description,
      " - Case: quote/base posthook fail with failing posthook (worst case) delta for taking deep order - cost for 1 successful and 19 failing offers"
    );
    printDescription();
  }

  function test_posthook_fail_delta_deep_order_quote_base() public {
    gasDeltaTest.posthook_delta_deep_order(lo);
    description = string.concat(
      description,
      " - Case: quote/base posthook fail with failing posthook (worst case) delta for taking deep order - cost for 1 successful and 19 failing offers"
    );
    printDescription();
  }

  function test_gasbase_transfers_estimate() public {
    uint outbound_gas = measureTransferGas($(base));
    uint inbound_gas = measureTransferGas($(quote));
    uint gasbase = 2 * (outbound_gas + inbound_gas);
    console.log("Gas used: %s", gasbase);
    description = string.concat(description, " - Case: ActivateSemibook transfers estimate");
    printDescription();
  }
}
