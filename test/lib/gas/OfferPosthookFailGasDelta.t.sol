// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MangroveTest, MgvReader, TestMaker, TestTaker, TestSender, console} from "@mgv/test/lib/MangroveTest.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {PinnedPolygonFork} from "@mgv/test/lib/forks/Polygon.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import "@mgv/src/core/MgvLib.sol";
import {Mangrove} from "@mgv/src/core/Mangrove.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {MIDDLE_BIN} from "@mgv/test/lib/gas/GasTestBase.t.sol";
import "@mgv/lib/Debug.sol";
import {TestTaker, IMaker} from "@mgv/test/lib/MangroveTest.sol";
import {GasTestBaseStored} from "@mgv/test/lib/gas/GasTestBase.t.sol";
import {Test2} from "@mgv/lib/Test2.sol";

/// A mangrove instrumented to measure gas usage during posthook
contract BeforePosthookGasMeasuringMangrove is Mangrove, Test2 {
  uint internal numberCall;

  constructor(address governance, uint gasprice, uint gasmax) Mangrove(governance, gasprice, gasmax) {
    // Warmup
    numberCall = 1;
  }

  function postExecute(
    MultiOrder memory mor,
    MgvLib.SingleOrder memory sor,
    uint gasused,
    bytes32 makerData,
    bytes32 mgvData
  ) internal virtual override {
    // We expect two calls, one for each successful offer, and then measure gas between them.
    if (numberCall == 1) {
      _gas();
    } else if (numberCall == 2) {
      gas_();
    }
    ++numberCall;
    super.postExecute(mor, sor, gasused, makerData, mgvData);
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
    mgv = IMangrove(
      payable(
        address(
          new BeforePosthookGasMeasuringMangrove({
          governance: $(this),
          gasprice: options.gasprice,
          gasmax: options.gasmax
          })
        )
      )
    );
    reader = new MgvReader($(mgv));
  }

  function setUpTokens(TestToken _base, TestToken _quote) public {
    base = _base;
    quote = _quote;

    olKey = OLKey($(base), $(quote), options.defaultTickSpacing);
    lo = OLKey($(quote), $(base), options.defaultTickSpacing);

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
    uint offerGivesOl = reader.minVolume(olKey, 100000);
    uint offerGivesLo = reader.minVolume(lo, 100000);

    vm.prank(maker);
    mgv.fund{value: 10 ether}();
    vm.prank(maker);
    TransferLib.approveToken(base, $(mgv), type(uint).max);
    vm.prank(maker);
    TransferLib.approveToken(quote, $(mgv), type(uint).max);

    // A successful offer (both offer lists)
    vm.prank(maker);
    mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), offerGivesOl, 10000, 0);
    vm.prank(maker);
    mgv.newOfferByTick(lo, lo.tick(MIDDLE_BIN), offerGivesLo, 10000, 0);

    // Do not approve maker - we will let offers fail since then penalty must be calculated, which costs gas.
    for (uint i; i < 19; i++) {
      mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), offerGivesOl, 10000, 0);
      mgv.newOfferByTick(lo, lo.tick(MIDDLE_BIN), offerGivesLo, 10000, 0);
    }

    // A successful offer (both offer lists)
    vm.prank(maker);
    mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), offerGivesOl, 10000, 0);
    vm.prank(maker);
    mgv.newOfferByTick(lo, lo.tick(MIDDLE_BIN), offerGivesLo, 10000, 0);
  }

  function posthook_delta_deep_order(OLKey memory olKey) public {
    vm.prank($(taker));
    mgv.marketOrderByTick({olKey: olKey, maxTick: olKey.tick(MIDDLE_BIN), fillVolume: 1 ether, fillWants: false});
  }
}
