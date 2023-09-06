// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {MgvLib, MgvStructs, Tick, Leaf, Field, LogPriceLib, OLKey} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import "mgv_lib/Debug.sol";

struct Market {
  address tkn0;
  address tkn1;
  uint tickScale;
}

/// @notice Config of a market. Assumes a context where `tkn0` and `tkn1` are defined. `config01` is the local config of the `tkn0/tkn1` offer list. `config10` is the config of the `tkn1/tkn0` offer list.
struct MarketConfig {
  MgvStructs.LocalUnpacked config01;
  MgvStructs.LocalUnpacked config10;
}

/// @notice We choose a canonical orientation for all markets based on the numerical values of their token addresses. That way we can uniquely identify a market with two addresses given in any order.
/// @return address the lowest of the given arguments (numerically)
/// @return address the highest of the given arguments (numerically)
function order(address tkn0, address tkn1) pure returns (address, address) {
  return uint160(tkn0) < uint160(tkn1) ? (tkn0, tkn1) : (tkn1, tkn0);
}

// canonically order the tokens of a Market
// modifies in-place
function order(Market memory market) pure {
  (market.tkn0, market.tkn1) = order(market.tkn0, market.tkn1);
}

// flip tkn0/tkn1 of a market. Useful before conversion to OLKey
// creates a copy
function flipped(Market memory market) pure returns (Market memory) {
  return Market(market.tkn1, market.tkn0, market.tickScale);
}

// convert Market to OLKey
// creates a copy
function toOLKey(Market memory market) pure returns (OLKey memory) {
  return OLKey(market.tkn0, market.tkn1, market.tickScale);
}

contract MgvReader {
  /**
   * @notice Open markets tracking (below) provides information about which markets on Mangrove are open. Anyone can update a market status by calling `updateMarket`.
   * @notice The array of structs `_openMarkets` is the array of all currently open markets (up to a delay in calling `updateMarkets`). A market is a triplet of tokens `(tkn0,tkn1,tickScale)`. The which token is 0 which token is 1 is non-meaningful but canonical (see `order`).
   * @notice In this contract, 'markets' are defined by non-oriented offerLists. Usually markets come with a base/quote orientation. Please keep that in mind.
   * @notice A market {tkn0,tkn1} is open if either the tkn0/tkn1 offer list is active or the tkn1/tkn0 offer list is active.
   */

  Market[] internal _openMarkets;

  /// @notice Markets can be added or removed from `_openMarkets` array. To remove a market, we must remember its position in the array. The `marketPositions` mapping does that. The mapping goes outbound => inbound => tickScale => positions.
  mapping(address => mapping(address => mapping(uint => uint))) internal marketPositions;

  IMangrove public immutable MGV;

  constructor(address mgv) {
    MGV = IMangrove(payable(mgv));
  }

  /// @return uint The number of open markets.
  function numOpenMarkets() external view returns (uint) {
    return _openMarkets.length;
  }

  /// @return markets all open markets
  /// @return configs the configs of each markets
  /// @notice If the ith market is [tkn0,tkn1], then the ith config will be a MarketConfig where config01 is the config for the tkn0/tkn1 offer list, and config10 is the config for the tkn1/tkn0 offer list.
  function openMarkets() external view returns (Market[] memory, MarketConfig[] memory) {
    return openMarkets(0, _openMarkets.length, true);
  }

  /// @notice List open markets, and optionally skip querying Mangrove for all the market configurations.
  /// @param withConfig if false, the second return value will be the empty array.
  /// @return Market[] all open markets
  /// @return MarketConfig[] corresponding configs, or the empty array if withConfig is false.
  function openMarkets(bool withConfig) external view returns (Market[] memory, MarketConfig[] memory) {
    return openMarkets(0, _openMarkets.length, withConfig);
  }

  /// @notice Get a slice of open markets, with accompanying market configs
  /// @return markets The following slice of _openMarkets: [from..min(_openMarkets.length,from+maxLen)]
  /// @return configs corresponding configs
  /// @dev throws if `from > _openMarkets.length`
  function openMarkets(uint from, uint maxLen)
    external
    view
    returns (Market[] memory markets, MarketConfig[] memory configs)
  {
    return openMarkets(from, maxLen, true);
  }

  /// @notice Get a slice of open markets, with accompanying market configs or not.
  /// @param withConfig if false, the second return value will be the empty array.
  /// @return markets The following slice of _openMarkets: [from..min(_openMarkets.length,from+maxLen)]
  /// @return configs corresponding configs, or the empty array if withConfig is false.
  /// @dev if there is a delay in updating a market, it is possible that an 'open market' (according to this contract) is not in fact open and that config01.active and config10.active are both false.
  /// @dev throws if `from > _openMarkets.length`
  function openMarkets(uint from, uint maxLen, bool withConfig)
    public
    view
    returns (Market[] memory markets, MarketConfig[] memory configs)
  {
    uint numMarkets = _openMarkets.length;
    if (from + maxLen > numMarkets) {
      maxLen = numMarkets - from;
    }
    markets = new Market[](maxLen);
    configs = new MarketConfig[](withConfig ? maxLen : 0);
    unchecked {
      for (uint i = 0; i < maxLen; ++i) {
        address tkn0 = _openMarkets[from + i].tkn0;
        address tkn1 = _openMarkets[from + i].tkn1;
        uint tickScale = _openMarkets[from + i].tickScale;
        // copy
        markets[i] = Market({tkn0: tkn0, tkn1: tkn1, tickScale: tickScale});

        if (withConfig) {
          configs[i].config01 = MGV.localUnpacked(toOLKey(markets[i]));
          configs[i].config10 = MGV.localUnpacked(toOLKey(flipped(markets[i])));
        }
      }
    }
  }

  /// @param market the market
  /// @return bool Whether the {tkn0,tkn1} market is open.
  /// @dev May not reflect the true state of the market on Mangrove if `updateMarket` was not called recently enough.
  function isMarketOpen(Market memory market) external view returns (bool) {
    (market.tkn0, market.tkn1) = order(market.tkn0, market.tkn1);
    return marketPositions[market.tkn0][market.tkn1][market.tickScale] > 0;
  }

  /// @notice return the configuration for the given market
  /// @param market the market
  /// @return config The market configuration. config01 and config10 follow the order given in arguments, not the canonical order
  /// @dev This function queries Mangrove so all the returned info is up-to-date.
  function marketConfig(Market memory market) external view returns (MarketConfig memory config) {
    config.config01 = MGV.localUnpacked(toOLKey(market));
    config.config10 = MGV.localUnpacked(toOLKey(flipped(market)));
  }

  /// @notice Permisionless update of _openMarkets array.
  /// @notice Will consider a market open iff either the offer lists tkn0/tkn1 or tkn1/tkn0 are open on Mangrove.
  function updateMarket(Market memory market) external {
    (market.tkn0, market.tkn1) = order(market.tkn0, market.tkn1);
    bool openOnMangrove = MGV.local(toOLKey(market)).active() || MGV.local(toOLKey(flipped(market))).active();
    uint position = marketPositions[market.tkn0][market.tkn1][market.tickScale];

    if (openOnMangrove && position == 0) {
      _openMarkets.push(market);
      marketPositions[market.tkn0][market.tkn1][market.tickScale] = _openMarkets.length;
    } else if (!openOnMangrove && position > 0) {
      uint numMarkets = _openMarkets.length;
      if (numMarkets > 1) {
        // avoid array holes
        Market memory lastMarket = _openMarkets[numMarkets - 1];

        _openMarkets[position - 1] = lastMarket;
        //FIXME add tests that check the last component (lastMarket.tickScale) is correct
        marketPositions[lastMarket.tkn0][lastMarket.tkn1][lastMarket.tickScale] = position;
      }
      _openMarkets.pop();
      marketPositions[market.tkn0][market.tkn1][market.tickScale] = 0;
    }
  }
}
