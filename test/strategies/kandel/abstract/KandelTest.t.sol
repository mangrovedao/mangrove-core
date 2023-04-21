// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/IERC20.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {MgvStructs, MgvLib} from "mgv_src/MgvLib.sol";
import {OfferType} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/TradesBaseQuotePair.sol";
import {CoreKandel, TransferLib} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/CoreKandel.sol";
import {GeometricKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {KandelLib} from "mgv_lib/kandel/KandelLib.sol";
import {console} from "forge-std/Test.sol";
import {MangroveTest} from "mgv_test/lib/MangroveTest.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {AbstractRouter} from "mgv_src/strategies/routers/AbstractRouter.sol";
import {AllMethodIdentifiersTest} from "mgv_test/lib/AllMethodIdentifiersTest.sol";

abstract contract KandelTest is MangroveTest {
  address payable maker;
  address payable taker;
  GeometricKandel kdl;
  uint8 constant STEP = 1;
  uint initQuote;
  uint initBase = 0.1 ether;
  uint globalGasprice;
  uint bufferedGasprice;

  OfferType constant Ask = OfferType.Ask;
  OfferType constant Bid = OfferType.Bid;
  uint PRECISION;

  event Mgv(IMangrove mgv);
  event Pair(IERC20 base, IERC20 quote);
  event NewKandel(address indexed owner, IMangrove indexed mgv, IERC20 indexed base, IERC20 quote);
  event SetGeometricParams(uint spread, uint ratio);
  event SetCompoundRates(uint compoundRateBase, uint compoundRateQuote);
  event SetLength(uint value);
  event SetGasreq(uint value);
  event Credit(IERC20 indexed token, uint amount);
  event Debit(IERC20 indexed token, uint amount);
  event PopulateStart();
  event PopulateEnd();
  event RetractStart();
  event RetractEnd();
  event LogIncident(
    IMangrove mangrove,
    IERC20 indexed outbound_tkn,
    IERC20 indexed inbound_tkn,
    uint indexed offerId,
    bytes32 makerData,
    bytes32 mgvData
  );

  // sets environement  default is local node with fake base and quote
  function __setForkEnvironment__() internal virtual {
    // no fork
    options.base.symbol = "WETH";
    options.quote.symbol = "USDC";
    options.quote.decimals = 6;
    options.defaultFee = 30;
    options.gasprice = 40;

    MangroveTest.setUp();
  }

  // defines how to deploy a Kandel strat
  function __deployKandel__(address deployer, address reserveId) internal virtual returns (GeometricKandel kdl_);

  function precisionForAssert() internal pure virtual returns (uint) {
    return 0;
  }

  function getAbiPath() internal pure virtual returns (string memory) {
    return "/out/Kandel.sol/Kandel.json";
  }

  function setUp() public virtual override {
    /// sets base, quote, opens a market (base,quote) on Mangrove
    __setForkEnvironment__();
    require(reader != MgvReader(address(0)), "Could not get reader");

    initQuote = cash(quote, 100); // quote given/wanted at index from

    maker = freshAddress("maker");
    taker = freshAddress("taker");
    deal($(base), taker, cash(base, 50));
    deal($(quote), taker, cash(quote, 70_000));

    // taker approves mangrove to be able to take offers
    vm.prank(taker);
    TransferLib.approveToken(base, $(mgv), type(uint).max);
    vm.prank(taker);
    TransferLib.approveToken(quote, $(mgv), type(uint).max);

    // deploy and activate
    (MgvStructs.GlobalPacked global,) = mgv.config(address(0), address(0));
    globalGasprice = global.gasprice();
    bufferedGasprice = globalGasprice * 10; // covering 10 times Mangrove's gasprice at deploy time

    kdl = __deployKandel__(maker, maker);
    PRECISION = kdl.PRECISION();

    // funding Kandel on Mangrove
    uint provAsk = reader.getProvision($(base), $(quote), kdl.offerGasreq(), bufferedGasprice);
    uint provBid = reader.getProvision($(quote), $(base), kdl.offerGasreq(), bufferedGasprice);
    deal(maker, (provAsk + provBid) * 10 ether);

    // maker approves Kandel to be able to deposit funds on it
    vm.prank(maker);
    TransferLib.approveToken(base, address(kdl), type(uint).max);
    vm.prank(maker);
    TransferLib.approveToken(quote, address(kdl), type(uint).max);

    uint ratio = 108 * 10 ** (PRECISION - 2);

    (CoreKandel.Distribution memory distribution1, uint lastQuote) =
      KandelLib.calculateDistribution(0, 5, initBase, initQuote, ratio, PRECISION);

    (CoreKandel.Distribution memory distribution2,) =
      KandelLib.calculateDistribution(5, 10, initBase, lastQuote, ratio, PRECISION);

    GeometricKandel.Params memory params;
    params.ratio = uint24(ratio);
    params.spread = STEP;
    params.pricePoints = 10;
    vm.prank(maker);
    kdl.populate{value: (provAsk + provBid) * 10}(distribution1, dynamic([uint(0), 1, 2, 3, 4]), 5, params, 0, 0);

    vm.prank(maker);
    kdl.populateChunk(distribution2, dynamic([uint(0), 1, 2, 3, 4]), 5);

    uint pendingBase = uint(-kdl.pending(Ask));
    uint pendingQuote = uint(-kdl.pending(Bid));
    deal($(base), maker, pendingBase);
    deal($(quote), maker, pendingQuote);

    expectFrom($(kdl));
    emit Credit(base, pendingBase);
    expectFrom($(kdl));
    emit Credit(quote, pendingQuote);
    vm.prank(maker);
    kdl.depositFunds(pendingBase, pendingQuote);
  }

  function buyFromBestAs(address taker_, uint amount) public returns (uint, uint, uint, uint, uint) {
    uint bestAsk = mgv.best($(base), $(quote));
    vm.prank(taker_);
    return mgv.snipes($(base), $(quote), wrap_dynamic([bestAsk, amount, type(uint96).max, type(uint).max]), true);
  }

  function sellToBestAs(address taker_, uint amount) internal returns (uint, uint, uint, uint, uint) {
    uint bestBid = mgv.best($(quote), $(base));
    vm.prank(taker_);
    return mgv.snipes($(quote), $(base), wrap_dynamic([bestBid, 0, amount, type(uint).max]), false);
  }

  function snipeBuyAs(address taker_, uint amount, uint index) internal returns (uint, uint, uint, uint, uint) {
    uint offerId = kdl.offerIdOfIndex(Ask, index);
    vm.prank(taker_);
    return mgv.snipes($(base), $(quote), wrap_dynamic([offerId, amount, type(uint96).max, type(uint).max]), true);
  }

  function snipeSellAs(address taker_, uint amount, uint index) internal returns (uint, uint, uint, uint, uint) {
    uint offerId = kdl.offerIdOfIndex(Bid, index);
    vm.prank(taker_);
    return mgv.snipes($(quote), $(base), wrap_dynamic([offerId, 0, amount, type(uint).max]), false);
  }

  function getParams(GeometricKandel aKandel) internal view returns (GeometricKandel.Params memory params) {
    (
      uint16 gasprice,
      uint24 gasreq,
      uint24 ratio,
      uint24 compoundRateBase,
      uint24 compoundRateQuote,
      uint8 spread,
      uint8 pricePoints
    ) = aKandel.params();

    params.gasprice = gasprice;
    params.gasreq = gasreq;
    params.ratio = ratio;
    params.compoundRateBase = compoundRateBase;
    params.compoundRateQuote = compoundRateQuote;
    params.spread = spread;
    params.pricePoints = pricePoints;
  }

  enum OfferStatus {
    Dead, // both dead
    Bid, // live bid
    Ask, // live ask
    Crossed // both live
  }

  struct IndexStatus {
    MgvStructs.OfferPacked bid;
    MgvStructs.OfferPacked ask;
    OfferStatus status;
  }

  function getStatus(uint index) internal view returns (IndexStatus memory idx) {
    idx.bid = kdl.getOffer(Bid, index);
    idx.ask = kdl.getOffer(Ask, index);
    if (idx.bid.gives() > 0 && idx.ask.gives() > 0) {
      idx.status = OfferStatus.Crossed;
    } else {
      if (idx.bid.gives() > 0) {
        idx.status = OfferStatus.Bid;
      } else {
        if (idx.ask.gives() > 0) {
          idx.status = OfferStatus.Ask;
        } else {
          idx.status = OfferStatus.Dead;
        }
      }
    }
  }

  ///@notice asserts status of index.
  function assertStatus(uint index, OfferStatus status) internal {
    assertStatus(index, status, type(uint).max, type(uint).max);
  }

  ///@notice asserts status of index and verifies price based on geometric progressing quote.
  function assertStatus(uint index, OfferStatus status, uint q, uint b) internal {
    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, index);
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, index);
    bool bidLive = mgv.isLive(bid);
    bool askLive = mgv.isLive(ask);

    if (status == OfferStatus.Dead) {
      assertTrue(!bidLive && !askLive, "offer at index is live");
    } else {
      if (status == OfferStatus.Bid) {
        assertTrue(bidLive && !askLive, "Kandel not bidding at index");
        if (q != type(uint).max) {
          assertApproxEqRel(
            bid.gives() * b, q * bid.wants(), 1e11, "Bid price does not follow distribution within 0.00001%"
          );
        }
      } else {
        if (status == OfferStatus.Ask) {
          assertTrue(!bidLive && askLive, "Kandel is not asking at index");
          if (q != type(uint).max) {
            assertApproxEqRel(
              ask.wants() * b, q * ask.gives(), 1e11, "Ask price does not follow distribution within 0.00001%"
            );
          }
        } else {
          assertTrue(bidLive && askLive, "Kandel is not crossed at index");
        }
      }
    }
  }

  function assertStatus(
    uint[] memory offerStatuses // 1:bid 2:ask 3:crossed 0:dead - see OfferStatus
  ) internal {
    assertStatus(offerStatuses, initQuote, initBase);
  }

  function assertStatus(
    uint[] memory offerStatuses, // 1:bid 2:ask 3:crossed 0:dead - see OfferStatus
    uint q, // initial quote at first price point, type(uint).max to ignore in verification
    uint b // initial base at first price point, type(uint).max to ignore in verification
  ) internal {
    uint expectedBids = 0;
    uint expectedAsks = 0;
    GeometricKandel.Params memory params = getParams(kdl);
    for (uint i = 0; i < offerStatuses.length; i++) {
      // `price = quote / initBase` used in assertApproxEqRel below
      OfferStatus offerStatus = OfferStatus(offerStatuses[i]);
      assertStatus(i, offerStatus, q, b);
      if (q != type(uint).max) {
        q = (q * uint(params.ratio)) / (10 ** PRECISION);
      }
      if (offerStatus == OfferStatus.Ask) {
        expectedAsks++;
      } else if (offerStatus == OfferStatus.Bid) {
        expectedBids++;
      } else if (offerStatus == OfferStatus.Crossed) {
        expectedAsks++;
        expectedBids++;
      }
    }

    (, uint[] memory bidIds,,) = reader.offerList(address(quote), address(base), 0, 1000);
    (, uint[] memory askIds,,) = reader.offerList(address(base), address(quote), 0, 1000);
    assertEq(expectedBids, bidIds.length, "Unexpected number of live bids on book");
    assertEq(expectedAsks, askIds.length, "Unexpected number of live asks on book");
  }

  enum ExpectedChange {
    Same,
    Increase,
    Decrease
  }

  function assertChange(ExpectedChange expectedChange, uint expected, uint actual, string memory descriptor) internal {
    if (expectedChange == ExpectedChange.Same) {
      assertApproxEqRel(expected, actual, 1e11, string.concat(descriptor, " should be unchanged to within 0.00001%"));
    } else if (expectedChange == ExpectedChange.Decrease) {
      assertGt(expected, actual, string.concat(descriptor, " should have decreased"));
    } else {
      assertLt(expected, actual, string.concat(descriptor, " should have increased"));
    }
  }

  function printOB() internal view {
    printOrderBook($(base), $(quote));
    printOrderBook($(quote), $(base));
    uint pendingBase = uint(kdl.pending(Ask));
    uint pendingQuote = uint(kdl.pending(Bid));

    console.log("-------", toUnit(pendingBase, 18), toUnit(pendingQuote, 6), "-------");
  }

  function populateSingle(
    GeometricKandel kandel,
    uint index,
    uint base,
    uint quote,
    uint pivotId,
    uint firstAskIndex,
    bytes memory expectRevert
  ) internal {
    GeometricKandel.Params memory params = getParams(kdl);
    populateSingle(
      kandel, index, base, quote, pivotId, firstAskIndex, params.pricePoints, params.ratio, params.spread, expectRevert
    );
  }

  function populateSingle(
    GeometricKandel kandel,
    uint index,
    uint base,
    uint quote,
    uint pivotId,
    uint firstAskIndex,
    uint pricePoints,
    uint ratio,
    uint spread,
    bytes memory expectRevert
  ) internal {
    CoreKandel.Distribution memory distribution;
    distribution.indices = new uint[](1);
    distribution.baseDist = new uint[](1);
    distribution.quoteDist = new uint[](1);
    uint[] memory pivotIds = new uint[](1);

    distribution.indices[0] = index;
    distribution.baseDist[0] = base;
    distribution.quoteDist[0] = quote;
    pivotIds[0] = pivotId;
    vm.prank(maker);
    if (expectRevert.length > 0) {
      vm.expectRevert(expectRevert);
    }
    GeometricKandel.Params memory params;
    params.pricePoints = uint8(pricePoints);
    params.ratio = uint24(ratio);
    params.spread = uint8(spread);

    kandel.populate{value: 0.1 ether}(distribution, pivotIds, firstAskIndex, params, 0, 0);
  }

  function populateFixedDistribution(uint size) internal returns (uint baseAmount, uint quoteAmount) {
    CoreKandel.Distribution memory distribution;

    distribution.indices = new uint[](size);
    distribution.baseDist = new uint[](size);
    distribution.quoteDist = new uint[](size);
    for (uint i; i < size; i++) {
      distribution.indices[i] = i;
      distribution.baseDist[i] = 1 ether;
      distribution.quoteDist[i] = 1500 * 10 ** 6 + i;
      if (i < size / 2) {
        quoteAmount += distribution.quoteDist[i];
      } else {
        baseAmount += distribution.baseDist[i];
      }
    }

    GeometricKandel.Params memory params = getParams(kdl);
    vm.prank(maker);
    kdl.populate{value: maker.balance}(distribution, new uint[](size), size / 2, params, 0, 0);
  }

  function getBestOffers() internal view returns (MgvStructs.OfferPacked bestBid, MgvStructs.OfferPacked bestAsk) {
    uint bestAskId = mgv.best($(base), $(quote));
    uint bestBidId = mgv.best($(quote), $(base));
    bestBid = mgv.offers($(quote), $(base), bestBidId);
    bestAsk = mgv.offers($(base), $(quote), bestAskId);
  }

  function getMidPrice() internal view returns (uint midWants, uint midGives) {
    (MgvStructs.OfferPacked bestBid, MgvStructs.OfferPacked bestAsk) = getBestOffers();

    midWants = bestBid.wants() * bestAsk.wants() + bestBid.gives() * bestAsk.gives();
    midGives = bestAsk.gives() * bestBid.wants() * 2;
  }

  function getDeadOffers(uint midGives, uint midWants)
    internal
    view
    returns (uint[] memory indices, uint[] memory quoteAtIndex, uint numBids)
  {
    GeometricKandel.Params memory params = getParams(kdl);

    uint[] memory indicesPre = new uint[](params.pricePoints);
    quoteAtIndex = new uint[](params.pricePoints);
    numBids = 0;

    uint quote = initQuote;

    // find missing offers
    uint numDead = 0;
    for (uint i = 0; i < params.pricePoints; i++) {
      OfferType ba = quote * midGives <= initBase * midWants ? Bid : Ask;
      MgvStructs.OfferPacked offer = kdl.getOffer(ba, i);
      if (!mgv.isLive(offer)) {
        if (ba == Bid) {
          numBids++;
        }
        indicesPre[numDead] = i;
        numDead++;
      }
      quoteAtIndex[i] = quote;
      quote = (quote * uint(params.ratio)) / 10 ** PRECISION;
    }

    // truncate indices - cannot do push to memory array
    indices = new uint[](numDead);
    for (uint i = 0; i < numDead; i++) {
      indices[i] = indicesPre[i];
    }
  }
}
