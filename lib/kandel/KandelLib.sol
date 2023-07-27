// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {CoreKandel, OfferType} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/CoreKandel.sol";
import {GeometricKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";
import {IERC20} from "mgv_src/IERC20.sol";

library KandelLib {
  function calculateDistribution(uint from, uint to, uint initBase, uint initQuote, uint ratio, uint precision)
    internal
    pure
    returns (CoreKandel.Distribution memory vars, uint lastQuote)
  {
    vars.indices = new uint[](to-from);
    vars.baseDist = new uint[](to-from);
    vars.quoteDist = new uint[](to-from);
    uint i = 0;
    for (; from < to; ++from) {
      vars.indices[i] = from;
      vars.baseDist[i] = initBase;
      vars.quoteDist[i] = initQuote;
      // the ratio gives the price difference between two price points - the spread is involved when calculating the jump between a bid and its dual ask.
      initQuote = (initQuote * uint(ratio)) / (10 ** precision);
      ++i;
    }
    return (vars, initQuote);
  }

  /// @notice should be invoked as an rpc call or via snapshot-revert - populates and returns pivots and amounts.
  function estimatePivotsAndRequiredAmount(
    CoreKandel.Distribution memory distribution,
    GeometricKandel kandel,
    uint firstAskIndex,
    GeometricKandel.Params memory params,
    uint funds
  ) internal returns (uint[] memory pivotIds, uint baseAmountRequired, uint quoteAmountRequired) {
    pivotIds = new uint[](distribution.indices.length);
    kandel.setParams(params);
    kandel.MGV().fund{value: funds}(address(kandel));
    kandel.populateChunk(distribution, pivotIds, firstAskIndex);
    for (uint i = 0; i < pivotIds.length; ++i) {
      uint index = distribution.indices[i];
      OfferType ba = index < firstAskIndex ? OfferType.Bid : OfferType.Ask;
      MgvStructs.OfferPacked offer = kandel.getOffer(ba, index);
      pivotIds[i] = offer.next();
      if (ba == OfferType.Bid) {
        quoteAmountRequired += offer.gives();
      } else {
        baseAmountRequired += offer.gives();
      }
    }
  }
}
