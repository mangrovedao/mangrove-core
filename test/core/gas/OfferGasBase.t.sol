// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MangroveTest, MgvReader, TestMaker, TestTaker, TestSender, console} from "mgv_test/lib/MangroveTest.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {GenericFork} from "mgv_test/lib/forks/Generic.sol";
import {TransferLib} from "mgv_lib/TransferLib.sol";
import {MgvStructs, MgvLib, IERC20} from "mgv_src/MgvLib.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {MIDDLE_LOG_PRICE} from "./GasTestBase.t.sol";
import {ActivateSemibook} from "mgv_script/core/ActivateSemibook.s.sol";
import "mgv_lib/Debug.sol";
import {IMangrove, TestTaker} from "mgv_test/lib/MangroveTest.sol";
import {GasTestBaseStored} from "./GasTestBase.t.sol";
import {OfferPosthookFailGasDeltaTest} from "./OfferPosthookFailGasDelta.t.sol";

abstract contract OfferGasBaseBaseTest is MangroveTest, GasTestBaseStored {
  TestTaker internal taker;
  GenericFork internal fork;
  OfferPosthookFailGasDeltaTest internal gasDeltaTest;

  function getStored() internal view override returns (IMangrove, TestTaker, OLKey memory, uint) {
    return (mgv, taker, olKey, 0);
  }

  function setUpGeneric() public virtual {
    super.setUp();
    fork = new GenericFork();
    fork.set(options.base.symbol, $(base));
    fork.set(options.quote.symbol, $(quote));
    gasDeltaTest = new OfferPosthookFailGasDeltaTest();
    gasDeltaTest.setUpGasTest(options);
    description = "Offer gasbase measurements";
  }

  function setUpPolygon() public virtual {
    super.setUp();
    fork = new PinnedPolygonFork();
    fork.setUp();
    options.gasprice = 90;
    options.gasbase = 200_000;
    options.defaultFee = 30;
    mgv = setupMangrove();
    reader = new MgvReader($(mgv));
    gasDeltaTest = new OfferPosthookFailGasDeltaTest();
    gasDeltaTest.setUpGasTest(options);
    description = "Offer gasbase measurements";
  }

  function setUpTokens(string memory baseToken, string memory quoteToken) public {
    description = string.concat(description, " - ", baseToken, "/", quoteToken);
    address baseAddress = fork.get(baseToken);
    address quoteAddress = fork.get(quoteToken);
    base = TestToken(baseAddress);
    quote = TestToken(quoteAddress);
    gasDeltaTest.setUpTokens(base, quote);
    olKey = OLKey($(base), $(quote), options.defaultTickScale);
    lo = OLKey($(quote), $(base), options.defaultTickScale);
    setupMarket(olKey);
    setupMarket(lo);

    taker = setupTaker(olKey, "Taker");
    deal($(base), address(taker), 200000 ether);
    deal($(quote), address(taker), 200000 ether);
    taker.approveMgv(quote, 200000 ether);
    taker.approveMgv(base, 200000 ether);

    address maker = freshAddress("Maker");
    deal($(base), maker, 200000 ether);
    deal($(quote), maker, 200000 ether);
    deal(maker, 1000 ether);
    uint offerGivesOl = reader.minVolume(olKey, 100000);
    uint offerGivesLo = reader.minVolume(lo, 100000);

    vm.prank(maker);
    mgv.fund{value: 10 ether}();
    vm.prank(maker);
    TransferLib.approveToken(base, $(mgv), type(uint).max);
    vm.prank(maker);
    TransferLib.approveToken(quote, $(mgv), type(uint).max);
    vm.prank(maker);
    mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, offerGivesOl, 100000, 0);
    vm.prank(maker);
    mgv.newOfferByLogPrice(lo, MIDDLE_LOG_PRICE, offerGivesLo, 100000, 0);
  }

  function gasbase_to_empty_book(OLKey memory _olKey) internal {
    (IMangrove _mgv,,,) = getStored();
    vm.prank($(taker));
    _gas();
    _mgv.marketOrderByLogPrice(_olKey, MIDDLE_LOG_PRICE, 1, false);
    gas_();
  }

  function test_gasbase_to_empty_book_base_quote() public {
    gasbase_to_empty_book(olKey);
    description = string.concat(description, " - Case: base/quote gasbase for taking single offer to empty book");
    printDescription();
  }

  function test_gasbase_to_empty_book_quote_base() public {
    gasbase_to_empty_book(lo);
    description = string.concat(description, " - Case: quote/base gasbase for taking single offer to empty book");
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
    ActivateSemibook semibook = new ActivateSemibook();
    uint outbound_gas = semibook.measureTransferGas($(base));
    uint inbound_gas = semibook.measureTransferGas($(quote));
    uint gasbase = 2 * (outbound_gas + inbound_gas);
    console.log("Gas used: %s", gasbase);
    description = string.concat(description, " - Case: ActivateSemibook transfers estimate");
    printDescription();
  }
}

contract OfferGasBaseTest_Generic_A_B is OfferGasBaseBaseTest {
  function setUp() public override {
    super.setUpGeneric();
    this.setUpTokens(options.base.symbol, options.quote.symbol);
  }
}

contract OfferGasBaseTest_Polygon_WETH_DAI is OfferGasBaseBaseTest {
  function setUp() public override {
    super.setUpPolygon();
    this.setUpTokens("WETH", "DAI");
  }
}
