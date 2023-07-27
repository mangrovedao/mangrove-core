// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MgvStructs} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {Kandel, OfferType, IERC20} from "mgv_src/strategies/offer_maker/market_making/kandel/Kandel.sol";
import {
  LongKandel, GeometricKandel
} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/LongKandel.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {KandelLib} from "lib/kandel/KandelLib.sol";
import {GeometricKandelTest} from "../abstract/GeometricKandel.t.sol";
import {console2} from "forge-std/Test.sol";

contract LongKandelTest is GeometricKandelTest {
  function setUp() public override {
    super.setUp();
    LongKandel kdl_ = LongKandel($(kdl));
    uint pendingBase = uint(-kdl.pending(Ask));
    uint pendingQuote = uint(-kdl.pending(Bid));
    deal($(base), maker, pendingBase);
    deal($(quote), maker, pendingQuote);
    expectFrom($(kdl));
    emit Credit(base, pendingBase);
    expectFrom($(kdl));
    emit Credit(quote, pendingQuote);
    vm.prank(maker);
    kdl_.depositFunds(pendingBase, pendingQuote);
  }

  function __deployKandel__(address deployer, address reserveId)
    internal
    virtual
    override
    returns (GeometricKandel kdl_)
  {
    uint GASREQ = 128_000; // can be 77_000 when all offers are initialized.

    vm.expectEmit(true, true, true, true);
    emit Mgv(IMangrove($(mgv)));
    vm.expectEmit(true, true, true, true);
    emit Pair(base, quote);
    vm.expectEmit(true, true, true, true);
    emit SetGasprice(bufferedGasprice);
    vm.expectEmit(true, true, true, true);
    emit SetGasreq(GASREQ);
    vm.prank(deployer);
    kdl_ = new Kandel({
      mgv: IMangrove($(mgv)),
      base: base,
      quote: quote,
      gasreq: GASREQ,
      gasprice: bufferedGasprice,
      reserveId: reserveId
    });
  }

  function deployOtherKandel(uint base0, uint quote0, uint24 ratio, uint8 spread, uint8 pricePoints) internal {
    address otherMaker = freshAddress();

    LongKandel otherKandel = LongKandel($(__deployKandel__(otherMaker, otherMaker)));

    vm.prank(otherMaker);
    TransferLib.approveToken(base, address(otherKandel), type(uint).max);
    vm.prank(otherMaker);
    TransferLib.approveToken(quote, address(otherKandel), type(uint).max);

    uint totalProvision = (
      reader.getProvision($(base), $(quote), otherKandel.offerGasreq(), bufferedGasprice)
        + reader.getProvision($(quote), $(base), otherKandel.offerGasreq(), bufferedGasprice)
    ) * 10 ether;

    deal(otherMaker, totalProvision);

    (GeometricKandel.Distribution memory distribution,) =
      KandelLib.calculateDistribution(0, pricePoints, base0, quote0, ratio, otherKandel.PRECISION());

    GeometricKandel.Params memory params;
    params.pricePoints = pricePoints;
    params.ratio = ratio;
    params.spread = spread;
    vm.prank(otherMaker);
    otherKandel.setParams(params);

    vm.prank(otherMaker);
    mgv.fund{value: totalProvision}($(otherKandel));

    vm.prank(otherMaker);
    otherKandel.populateChunk(distribution, new uint[](pricePoints), pricePoints / 2);

    uint pendingBase = uint(-otherKandel.pending(Ask));
    uint pendingQuote = uint(-otherKandel.pending(Bid));
    deal($(base), otherMaker, pendingBase);
    deal($(quote), otherMaker, pendingQuote);

    vm.prank(otherMaker);
    otherKandel.depositFunds(pendingBase, pendingQuote);
  }

  function retractDefaultSetup() internal {
    uint baseFunds = kdl.offeredVolume(Ask) + uint(kdl.pending(Ask));
    uint quoteFunds = kdl.offeredVolume(Bid) + uint(kdl.pending(Bid));
    vm.prank(maker);
    LongKandel($(kdl)).retractAndWithdraw(0, 10, baseFunds, quoteFunds, type(uint).max, maker);
  }

  // adding pending tests after ask complete_fill which are specific to LongKandel
  function ask_complete_fill(uint24 compoundRateBase, uint24 compoundRateQuote, uint index)
    internal
    virtual
    override
    returns (uint takerGot, uint takerGave, uint fee)
  {
    int oldPending = kdl.pending(Bid);
    MgvStructs.OfferPacked oldBid = kdl.getOffer(Bid, index - STEP);

    (takerGot, takerGave, fee) = super.ask_complete_fill(compoundRateBase, compoundRateQuote, index);

    int pendingDelta = kdl.pending(Bid) - oldPending;
    MgvStructs.OfferPacked newBid = kdl.getOffer(Bid, index - STEP);

    assertApproxEqAbs(
      pendingDelta + int(newBid.gives()),
      int(oldBid.gives() + takerGave),
      precisionForAssert(),
      "Incorrect net promised asset"
    );
    if (compoundRateQuote == full_compound()) {
      assertApproxEqAbs(pendingDelta, 0, precisionForAssert(), "Full compounding should not yield pending");
    } else {
      assertTrue(pendingDelta > 0, "Partial auto compounding should yield pending");
    }
  }

  function bid_complete_fill(uint24 compoundRateBase, uint24 compoundRateQuote, uint index)
    internal
    override
    returns (uint takerGot, uint takerGave, uint fee)
  {
    MgvStructs.OfferPacked oldAsk = kdl.getOffer(Ask, index + STEP);
    int oldPending = kdl.pending(Ask);
    (takerGot, takerGave, fee) = super.bid_complete_fill(compoundRateBase, compoundRateQuote, index);
    MgvStructs.OfferPacked newAsk = kdl.getOffer(Ask, index + STEP);
    int pendingDelta = kdl.pending(Ask) - oldPending;
    // Allow a discrepancy of 1 for aave router shares
    assertApproxEqAbs(
      pendingDelta + int(newAsk.gives()),
      int(oldAsk.gives() + takerGave),
      precisionForAssert(),
      "Incorrect net promised asset"
    );
    if (compoundRateBase == full_compound()) {
      assertApproxEqAbs(pendingDelta, 0, precisionForAssert(), "Full compounding should not yield pending");
    } else {
      assertTrue(pendingDelta > 0, "Partial auto compounding should yield pending");
    }
  }

  function test_init() public {
    assertEq(kdl.pending(Ask), kdl.pending(Bid), "Incorrect initial pending");
    assertEq(kdl.pending(Ask), 0, "Incorrect initial pending");
  }

  function test_reserveBalance_withoutOffers_returnsFundAmount() public {
    // Arrange
    retractDefaultSetup();
    assertEq(kdl.reserveBalance(Ask), 0, "Base balance should be empty");
    assertEq(kdl.reserveBalance(Bid), 0, "Quote balance should be empty");

    vm.prank(maker);
    LongKandel($(kdl)).depositFunds(42, 43);

    // Act/assert
    assertEq(kdl.reserveBalance(Ask), 42, "Base balance should be correct");
    assertEq(kdl.reserveBalance(Bid), 43, "Quote balance should be correct");
  }

  function test_reserveBalance_withOffers_returnsFundAmount() public {
    // Arrange
    retractDefaultSetup();
    populateFixedDistribution(4);

    assertEq(kdl.reserveBalance(Ask), 0, "Base balance should be empty");
    assertEq(kdl.reserveBalance(Bid), 0, "Quote balance should be empty");

    vm.prank(maker);
    LongKandel($(kdl)).depositFunds(42, 43);

    // Act/assert
    assertEq(kdl.reserveBalance(Ask), 42, "Base balance should be correct");
    assertEq(kdl.reserveBalance(Bid), 43, "Quote balance should be correct");
  }

  function test_offeredVolume_withOffers_returnsSumOfGives() public {
    // Arrange
    retractDefaultSetup();

    (uint baseAmount, uint quoteAmount) = populateFixedDistribution(4);

    // Act/assert
    assertEq(kdl.offeredVolume(Bid), quoteAmount, "Bid volume should be sum of quote dist");
    assertEq(kdl.offeredVolume(Ask), baseAmount, "Ask volume should be sum of base dist");
  }

  function test_pending_withoutOffers_returnsReserveBalance() public {
    // Arrange
    retractDefaultSetup();
    assertEq(kdl.pending(Ask), 0, "Base pending should be empty");
    assertEq(kdl.pending(Bid), 0, "Quote pending should be empty");

    vm.prank(maker);
    LongKandel($(kdl)).depositFunds(42, 43);

    // Act/assert
    assertEq(kdl.pending(Ask), 42, "Base pending should be correct");
    assertEq(kdl.pending(Bid), 43, "Quote pending should be correct");
  }

  function test_pending_withOffers_disregardsOfferedVolume() public {
    // Arrange
    retractDefaultSetup();
    (uint baseAmount, uint quoteAmount) = populateFixedDistribution(4);

    assertEq(-kdl.pending(Ask), int(baseAmount), "Base pending should be correct");
    assertEq(-kdl.pending(Bid), int(quoteAmount), "Quote pending should be correct");

    vm.prank(maker);
    LongKandel($(kdl)).depositFunds(42, 43);

    assertEq(-kdl.pending(Ask), int(baseAmount - 42), "Base pending should be correct");
    assertEq(-kdl.pending(Bid), int(quoteAmount - 43), "Quote pending should be correct");
  }

  function test_populate_allBids_successful() public {
    populate_allBidsAsks_successful(true);
  }

  function test_populate_allAsks_successful() public {
    populate_allBidsAsks_successful(false);
  }

  function populate_allBidsAsks_successful(bool bids) internal {
    retractDefaultSetup();

    GeometricKandel.Distribution memory distribution;
    distribution.indices = dynamic([uint(0), 1, 2, 3]);
    distribution.baseDist = dynamic([uint(1 ether), 1 ether, 1 ether, 1 ether]);
    distribution.quoteDist = dynamic([uint(1 ether), 1 ether, 1 ether, 1 ether]);

    uint firstAskIndex = bids ? 4 : 0;
    vm.prank(maker);
    mgv.fund{value: maker.balance}($(kdl));
    vm.prank(maker);
    kdl.populateChunk(distribution, new uint[](4), firstAskIndex);

    uint status = bids ? uint(OfferStatus.Bid) : uint(OfferStatus.Ask);
    assertStatus(dynamic([status, status, status, status]), type(uint).max, type(uint).max);
  }

  function test_estimatePivotsAndRequiredAmount_withPivots_savesGas() public {
    // Arrange
    retractDefaultSetup();

    // Use a large number of price points - the rest of the parameters are not too important
    GeometricKandel.Params memory params;
    params.ratio = uint24(108 * 10 ** PRECISION / 100);
    params.pricePoints = 100;
    params.spread = STEP;

    TestPivot memory t;
    t.firstAskIndex = params.pricePoints / 2;
    t.funds = 20 ether;

    // Make sure there are some other offers that can end up as pivots - we deploy a couple of Kandels
    deployOtherKandel(initBase + 1, initQuote + 1, params.ratio, params.spread, params.pricePoints);
    deployOtherKandel(initBase + 100, initQuote + 100, params.ratio, params.spread, params.pricePoints);

    (GeometricKandel.Distribution memory distribution,) = KandelLib.calculateDistribution({
      from: 0,
      to: params.pricePoints,
      initBase: initBase,
      initQuote: initQuote,
      ratio: params.ratio,
      precision: PRECISION
    });

    // Get some reasonable pivots (use a snapshot to avoid actually posting offers yet)
    t.snapshotId = vm.snapshot();
    vm.prank(maker);
    (t.pivotIds, t.baseAmountRequired, t.quoteAmountRequired) =
      KandelLib.estimatePivotsAndRequiredAmount(distribution, LongKandel($(kdl)), t.firstAskIndex, params, t.funds);
    require(vm.revertTo(t.snapshotId), "snapshot restore failed");

    // Make sure we have enough funds
    deal($(base), maker, t.baseAmountRequired);
    deal($(quote), maker, t.quoteAmountRequired);

    // Act

    // Populate with 0-pivots
    t.snapshotId = vm.snapshot();
    vm.prank(maker);
    t.gas0Pivot = gasleft();
    LongKandel($(kdl)).populate{value: t.funds}({
      distribution: distribution,
      firstAskIndex: t.firstAskIndex,
      parameters: params,
      pivotIds: new uint[](params.pricePoints),
      baseAmount: t.baseAmountRequired,
      quoteAmount: t.quoteAmountRequired
    });
    t.gas0Pivot = t.gas0Pivot - gasleft();

    require(vm.revertTo(t.snapshotId), "second snapshot restore failed");

    // Populate with pivots
    vm.prank(maker);
    t.gasPivots = gasleft();
    LongKandel($(kdl)).populate{value: t.funds}({
      distribution: distribution,
      firstAskIndex: t.firstAskIndex,
      parameters: params,
      pivotIds: t.pivotIds,
      baseAmount: t.baseAmountRequired,
      quoteAmount: t.quoteAmountRequired
    });
    t.gasPivots = t.gasPivots - gasleft();

    // Assert

    assertApproxEqAbs(0, kdl.pending(OfferType.Ask), precisionForAssert(), "required base amount should be deposited");
    assertApproxEqAbs(0, kdl.pending(OfferType.Bid), precisionForAssert(), "required quote amount should be deposited");

    //   console.log("No pivot populate: %s PivotPopulate: %s", t.gas0Pivot, t.gasPivots);

    assertLt(t.gasPivots, t.gas0Pivot, "Providing pivots should save gas");
  }

  function heal(uint midWants, uint midGives, uint densityBid, uint densityAsk) internal {
    // user can adjust pending by withdrawFunds or transferring to Kandel, then invoke heal.
    // heal fills up offers to some designated volume starting from mid-price.
    // Designated volume should either be equally divided between holes, or be based on Kandel Density
    // Here we assume its some constant.
    // Note this example implementation
    // * does not support no bids
    // * uses initQuote/initBase as starting point - not available on-chain
    // * assumes mid-price and bid/asks on the book are not crossed.

    uint baseDensity = densityBid;
    uint quoteDensity = densityAsk;

    (uint[] memory indices, uint[] memory quoteAtIndex, uint numBids) = getDeadOffers(midGives, midWants);

    // build arrays for populate
    uint[] memory quoteDist = new uint[](indices.length);
    uint[] memory baseDist = new uint[](indices.length);

    uint pendingQuote = uint(kdl.pending(Bid));
    uint pendingBase = uint(kdl.pending(Ask));

    if (numBids > 0 && baseDensity * numBids < pendingQuote) {
      baseDensity = pendingQuote / numBids; // fill up (a tiny bit lost to rounding)
    }
    // fill up close to mid price first
    for (int i = int(numBids) - 1; i >= 0; i--) {
      uint d = pendingQuote < baseDensity ? pendingQuote : baseDensity;
      pendingQuote -= d;
      quoteDist[uint(i)] = d;
      baseDist[uint(i)] = initBase * d / quoteAtIndex[indices[uint(i)]];
    }

    uint numAsks = indices.length - numBids;
    if (numAsks > 0 && quoteDensity * numAsks < pendingBase) {
      quoteDensity = pendingBase / numAsks; // fill up (a tiny bit lost to rounding)
    }
    // fill up close to mid price first
    for (uint i = numBids; i < indices.length; i++) {
      uint d = pendingBase < quoteDensity ? pendingBase : quoteDensity;
      pendingBase -= d;
      baseDist[uint(i)] = d;
      quoteDist[uint(i)] = quoteAtIndex[indices[uint(i)]] * d / initBase;
    }

    uint firstAskIndex = numAsks > 0 ? indices[numBids] : indices[indices.length - 1] + 1;
    uint[] memory pivotIds = new uint[](indices.length);
    GeometricKandel.Distribution memory distribution;
    distribution.indices = indices;
    distribution.baseDist = baseDist;
    distribution.quoteDist = quoteDist;
    vm.prank(maker);
    kdl.populateChunk(distribution, pivotIds, firstAskIndex);
  }

  function heal_someFailedOffers_reposts(OfferType ba, uint failures, uint[] memory expectedMidStatus) internal {
    // Arrange
    (uint midWants, uint midGives) = getMidPrice();
    (MgvStructs.OfferPacked bestBid, MgvStructs.OfferPacked bestAsk) = getBestOffers();
    uint densityMidBid = bestBid.gives();
    uint densityMidAsk = bestAsk.gives();
    IERC20 outbound = ba == OfferType.Ask ? base : quote;

    // Fail some offers - make offers fail by removing approval
    vm.prank(maker);
    kdl.approve(outbound, $(mgv), 0);
    for (uint i = 0; i < failures; i++) {
      // This will emit LogIncident and OfferFail
      (uint successes,,,,) = ba == Ask ? buyFromBestAs(taker, 1 ether) : sellToBestAs(taker, 1 ether);
      assertTrue(successes == 0, "Snipe should fail");
    }

    // verify offers have gone
    assertStatus(expectedMidStatus);

    // reduce pending volume to let heal only use some of the original volume when healing
    uint halfPending = uint(kdl.pending(ba)) / 2;
    vm.prank(maker);
    uint baseAmount = ba == Ask ? halfPending : 0;
    uint quoteAmount = ba == Ask ? 0 : halfPending;
    LongKandel($(kdl)).withdrawFunds(baseAmount, quoteAmount, maker);

    // Act
    heal(midWants, midGives, densityMidBid / 2, densityMidAsk / 2);

    // Assert - verify status and prices
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
  }

  function test_heal_1FailedAsk_reposts() public {
    heal_someFailedOffers_reposts(Ask, 1, dynamic([uint(1), 1, 1, 1, 1, 0, 2, 2, 2, 2]));
  }

  function test_heal_1FailedBid_reposts() public {
    heal_someFailedOffers_reposts(Bid, 1, dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
  }

  function test_heal_3FailedAsk_reposts() public {
    heal_someFailedOffers_reposts(Ask, 3, dynamic([uint(1), 1, 1, 1, 1, 0, 0, 0, 2, 2]));
  }

  function test_heal_3FailedBid_reposts() public {
    heal_someFailedOffers_reposts(Bid, 3, dynamic([uint(1), 1, 0, 0, 0, 2, 2, 2, 2, 2]));
  }

  function test_retractAndWithdraw() public {
    address payable recipient = freshAddress();
    uint baseBalance = kdl.reserveBalance(Ask);
    uint quoteBalance = kdl.reserveBalance(Bid);
    expectFrom($(kdl));
    emit Debit(base, baseBalance);
    expectFrom($(kdl));
    emit Debit(quote, quoteBalance);
    vm.prank(maker);
    LongKandel($(kdl)).retractAndWithdraw(0, 10, baseBalance, quoteBalance, type(uint).max, recipient);

    assertEq(quoteBalance, quote.balanceOf(recipient), "quote balance should be sent to recipient");
    assertEq(baseBalance, base.balanceOf(recipient), "quote balance should be sent to recipient");
    assertGt(recipient.balance, 0, "wei should be at recipient");
    assertEq(0, kdl.offeredVolume(Bid), "no bids should be live");
    assertEq(0, kdl.offeredVolume(Ask), "no bids should be live");
  }

  function test_depositFunds(uint96 baseAmount, uint96 quoteAmount) public {
    deal($(base), address(this), baseAmount);
    deal($(quote), address(this), quoteAmount);
    TransferLib.approveToken(base, $(kdl), baseAmount);
    TransferLib.approveToken(quote, $(kdl), quoteAmount);

    uint quoteBalance = kdl.reserveBalance(Bid);
    uint baseBalance = kdl.reserveBalance(Ask);

    LongKandel($(kdl)).depositFunds(baseAmount, quoteAmount);

    assertApproxEqRel(baseBalance + baseAmount, kdl.reserveBalance(Ask), 10 ** 10, "Incorrect base deposit");
    assertApproxEqRel(quoteBalance + quoteAmount, kdl.reserveBalance(Bid), 10 ** 10, "Incorrect base deposit");
  }

  function test_deposit0Funds() public {
    uint quoteBalance = kdl.reserveBalance(Bid);
    uint baseBalance = kdl.reserveBalance(Ask);
    LongKandel($(kdl)).depositFunds(0, 0);
    assertEq(kdl.reserveBalance(Ask), baseBalance, "Incorrect base deposit");
    assertEq(kdl.reserveBalance(Bid), quoteBalance, "Incorrect quote deposit");
  }

  function test_withdrawFunds(uint96 baseAmount, uint96 quoteAmount) public {
    deal($(base), address(this), baseAmount);
    deal($(quote), address(this), quoteAmount);
    TransferLib.approveToken(base, $(kdl), baseAmount);
    TransferLib.approveToken(quote, $(kdl), quoteAmount);

    LongKandel($(kdl)).depositFunds(baseAmount, quoteAmount);

    vm.prank(maker);
    LongKandel($(kdl)).withdrawFunds(baseAmount, quoteAmount, address(this));
    assertEq(base.balanceOf(address(this)), baseAmount, "Incorrect base withdrawal");
    assertEq(quote.balanceOf(address(this)), quoteAmount, "Incorrect quote withdrawl");
  }

  function test_withdrawAll() public {
    deal($(base), address(this), 1 ether);
    deal($(quote), address(this), 100 * 10 ** 6);
    TransferLib.approveToken(base, $(kdl), 1 ether);
    TransferLib.approveToken(quote, $(kdl), 100 * 10 ** 6);

    LongKandel($(kdl)).depositFunds(1 ether, 100 * 10 ** 6);
    uint quoteBalance = kdl.reserveBalance(Bid);
    uint baseBalance = kdl.reserveBalance(Ask);

    vm.prank(maker);
    LongKandel($(kdl)).withdrawFunds(type(uint).max, type(uint).max, address(this));
    assertEq(base.balanceOf(address(this)), baseBalance, "Incorrect base withdrawal");
    assertEq(quote.balanceOf(address(this)), quoteBalance, "Incorrect quote withdrawl");
  }
}
