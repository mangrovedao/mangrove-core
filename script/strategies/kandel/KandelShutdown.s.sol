// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";
import {GeometricKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {OfferType} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/TradesBaseQuotePair.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/**
 * @notice Populate Kandel's distribution on Mangrove
 */

contract KandelShutdown is Deployer {
  function run() public {
    innerRun({kdl: GeometricKandel(envAddressOrName("KANDEL"))});
  }

  function innerRun(GeometricKandel kdl) public {
    IERC20 base = kdl.BASE();
    IERC20 quote = kdl.QUOTE();
    uint baseDecimals = base.decimals();
    uint quoteDecimals = quote.decimals();
    (,,,,,, uint8 length) = kdl.params();

    uint baseBalance = base.balanceOf(broadcaster());
    uint quoteBalance = quote.balanceOf(broadcaster());
    uint weiBalance = broadcaster().balance;

    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = base;
    tokens[1] = quote;
    uint[] memory tokenAmounts = new uint[](2);
    tokenAmounts[0] = kdl.reserveBalance(OfferType.Ask); // base balance
    tokenAmounts[1] = kdl.reserveBalance(OfferType.Bid); // quote balance

    broadcast();
    kdl.retractAndWithdraw(0, length, tokens, tokenAmounts, type(uint).max, payable(broadcaster()));

    baseBalance = base.balanceOf(broadcaster()) - baseBalance;
    quoteBalance = quote.balanceOf(broadcaster()) - quoteBalance;
    weiBalance = broadcaster().balance - weiBalance;

    console.log(
      "Recovered %s base, %s quote and %s native tokens",
      toUnit(baseBalance, baseDecimals),
      toUnit(quoteBalance, quoteDecimals),
      toUnit(weiBalance, 18)
    );

    console.log("Retrieving pending...");
    int pendingBase = kdl.pending(OfferType.Ask);
    int pendingQuote = kdl.pending(OfferType.Bid);

    tokenAmounts[0] = (pendingBase > 0 ? uint(pendingBase) : 0);
    tokenAmounts[1] = (pendingQuote > 0 ? uint(pendingQuote) : 0);
    broadcast();
    kdl.withdrawFunds(tokens, tokenAmounts, broadcaster());

    console.log(
      "Retrieved %s base and %s quote tokens",
      toUnit(tokenAmounts[0], baseDecimals),
      toUnit(tokenAmounts[1], quoteDecimals)
    );
  }
}
