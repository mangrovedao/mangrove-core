// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";
import {LongKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/LongKandel.sol";
import {OfferType} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/TradesBaseQuotePair.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/**
 * @notice Populate Kandel's distribution on Mangrove
 */

contract KandelShutdown is Deployer {
  function run() public {
    innerRun({kdl: LongKandel(envAddressOrName("KANDEL"))});
  }

  function innerRun(LongKandel kdl) public {
    IERC20 base = kdl.BASE();
    IERC20 quote = kdl.QUOTE();
    uint baseDecimals = base.decimals();
    uint quoteDecimals = quote.decimals();
    (,,,,,, uint8 length) = kdl.params();

    uint baseBalance = base.balanceOf(broadcaster());
    uint quoteBalance = quote.balanceOf(broadcaster());
    uint weiBalance = broadcaster().balance;

    uint baseAmount = kdl.reserveBalance(OfferType.Ask); // base balance
    uint quoteAmount = kdl.reserveBalance(OfferType.Bid); // quote balance

    broadcast();
    kdl.retractAndWithdraw(0, length, baseAmount, quoteAmount, type(uint).max, payable(broadcaster()));

    baseBalance = base.balanceOf(broadcaster()) - baseBalance;
    quoteBalance = quote.balanceOf(broadcaster()) - quoteBalance;
    weiBalance = broadcaster().balance - weiBalance;

    console.log(
      "Recovered %s base, %s quote and %s native tokens",
      toFixed(baseBalance, baseDecimals),
      toFixed(quoteBalance, quoteDecimals),
      toFixed(weiBalance, 18)
    );

    console.log("Retrieving pending...");
    int pendingBase = kdl.pending(OfferType.Ask);
    int pendingQuote = kdl.pending(OfferType.Bid);

    baseAmount = (pendingBase > 0 ? uint(pendingBase) : 0);
    quoteAmount = (pendingQuote > 0 ? uint(pendingQuote) : 0);
    broadcast();
    kdl.withdrawFunds(baseAmount, quoteAmount, broadcaster());

    console.log(
      "Retrieved %s base and %s quote tokens", toFixed(baseAmount, baseDecimals), toFixed(quoteAmount, quoteDecimals)
    );
  }
}
