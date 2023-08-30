// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MangroveTest, MgvReader, TestMaker, TestTaker, TestSender, console} from "mgv_test/lib/MangroveTest.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {TransferLib} from "mgv_lib/TransferLib.sol";
import {MgvStructs, MgvLib, IERC20} from "mgv_src/MgvLib.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {MIDDLE_LOG_PRICE} from "./GasTestBase.t.sol";
import {ActivateSemibook} from "mgv_script/core/ActivateSemibook.s.sol";
import "mgv_lib/Debug.sol";
import {AbstractMangrove, TestTaker, IMaker} from "mgv_test/lib/MangroveTest.sol";
import {GasTestBaseStored} from "./GasTestBase.t.sol";
import {Test2} from "mgv_lib/Test2.sol";

/// A mangrove instrumented to measure gas usage during posthook
contract BeforePosthookGasMeasuringMangrove is AbstractMangrove, Test2 {
  uint internal numberCall;

  constructor(address governance, uint gasprice, uint gasmax)
    AbstractMangrove(governance, gasprice, gasmax, "Mangrove")
  {
    // Warmup
    numberCall = 1;
  }

  function executeEnd(MultiOrder memory, MgvLib.SingleOrder memory) internal override {}

  function beforePosthook(MgvLib.SingleOrder memory) internal override {
    // We expect two calls, one for each successful offer, and then measure gas between them.
    if (numberCall == 1) {
      _gas();
    } else if (numberCall == 2) {
      gas_();
    }
    ++numberCall;
  }

  // Identical to the one in Mangrove.sol
  function flashloan(MgvLib.SingleOrder calldata sor, address taker)
    external
    override
    returns (uint gasused, bytes32 makerData)
  {
    unchecked {
      /* `flashloan` must be used with a call (hence the `external` modifier) so its effect can be reverted. But a call from the outside would be fatal. */
      require(msg.sender == address(this), "mgv/flashloan/protected");
      /* The transfer taker -> maker is in 2 steps. First, taker->mgv. Then
       mgv->maker. With a direct taker->maker transfer, if one of taker/maker
       is blacklisted, we can't tell which one. We need to know which one:
       if we incorrectly blame the taker, a blacklisted maker can block an offer list forever; if we incorrectly blame the maker, a blacklisted taker can unfairly make makers fail all the time. Of course we assume that Mangrove is not blacklisted. This 2-step transfer is incompatible with tokens that have transfer fees (more accurately, it uselessly incurs fees twice). */
      if (transferTokenFrom(sor.olKey.inbound, taker, address(this), sor.gives)) {
        if (transferToken(sor.olKey.inbound, sor.offerDetail.maker(), sor.gives)) {
          (gasused, makerData) = makerExecute(sor);
        } else {
          innerRevert([bytes32("mgv/makerReceiveFail"), bytes32(0), ""]);
        }
      } else {
        innerRevert([bytes32("mgv/takerTransferFail"), "", ""]);
      }
    }
  }
}

/// This test is used by OfferGasBaseBaseTest to measure the gas cost of unrolling the stack during market orders which is dominated by posthook.
/// Posthook part is most expensive when 1) makerExecute fails (due to penalty accounting) and 2) postHook fails (due to event emitted)
/// So that is the scenario tested here. However, to measure during unrolling we use the `beforePosthook` hook which is only
/// invoked for successful offers, so we wrap 19 failing offers in 2 successful offers, which effective measures gas for 19 failures and 1 success.
contract OfferPosthookFailGasDeltaTest is MangroveTest, IMaker {
  TestTaker internal taker;

  function makerExecute(MgvLib.SingleOrder calldata) external virtual returns (bytes32) {
    return ""; // silence unused function parameter
  }

  function makerPosthook(MgvLib.SingleOrder calldata, MgvLib.OrderResult calldata) external virtual override {
    // Revert to simulate failure without spending too much gas.
    revert("AH AH AH!");
  }

  function setUpGasTest(MangroveTestOptions memory options) public {
    mgv = new BeforePosthookGasMeasuringMangrove({
        governance: $(this),
        gasprice: options.gasprice,
        gasmax: options.gasmax
      });
  }

  function setUpTokens(TestToken _base, TestToken _quote) public {
    base = _base;
    quote = _quote;

    olKey = OLKey($(base), $(quote), options.defaultTickscale);
    lo = OLKey($(quote), $(base), options.defaultTickscale);

    setupMarket(olKey);
    setupMarket(lo);

    taker = setupTaker(olKey, "Taker2");
    deal($(base), $(taker), 200000 ether);
    deal($(quote), $(taker), 200000 ether);
    taker.approveMgv(quote, 200000 ether);
    taker.approveMgv(base, 200000 ether);

    deal($(this), 1000 ether);
    mgv.fund{value: 10 ether}();

    address maker = freshAddress("Maker2");
    deal($(base), maker, 200000 ether);
    deal($(quote), maker, 200000 ether);
    deal(maker, 1000 ether);
    vm.prank(maker);
    mgv.fund{value: 10 ether}();
    vm.prank(maker);
    TransferLib.approveToken(base, $(mgv), type(uint).max);
    vm.prank(maker);
    TransferLib.approveToken(quote, $(mgv), type(uint).max);

    // A successful offer (both offer lists)
    vm.prank(maker);
    mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 1, 10000, 0);
    vm.prank(maker);
    mgv.newOfferByLogPrice(lo, MIDDLE_LOG_PRICE, 1, 10000, 0);

    // Do not approve maker - we will let offers fail since then penalty must be calculated, which costs gas.
    for (uint i; i < 19; i++) {
      mgv.newOfferByLogPrice(lo, MIDDLE_LOG_PRICE, 1, 10000, 0);
      mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 1, 10000, 0);
    }

    // A successful offer (both offer lists)
    vm.prank(maker);
    mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 1, 10000, 0);
    vm.prank(maker);
    mgv.newOfferByLogPrice(lo, MIDDLE_LOG_PRICE, 1, 10000, 0);
  }

  function posthook_delta_deep_order(OLKey memory olKey) public {
    vm.prank($(taker));
    mgv.marketOrderByLogPrice({olKey: olKey, maxLogPrice: MIDDLE_LOG_PRICE, fillVolume: 1 ether, fillWants: false});
  }
}
