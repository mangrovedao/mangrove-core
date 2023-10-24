// SPDX-License-Identifier: Unlicense
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

    uint baseAmount = kdl.reserveBalance(OfferType.Ask); // base balance
    uint quoteAmount = kdl.reserveBalance(OfferType.Bid); // quote balance

    broadcast();
    kdl.retractAndWithdraw(0, length, baseAmount, quoteAmount, type(uint).max, payable(broadcaster()));

    baseBalance = base.balanceOf(broadcaster()) - baseBalance;
    quoteBalance = quote.balanceOf(broadcaster()) - quoteBalance;
    weiBalance = broadcaster().balance - weiBalance;

    console.log(
      "* Script should recover %s base, %s quote and %s native tokens",
      toFixed(baseBalance, baseDecimals),
      toFixed(quoteBalance, quoteDecimals),
      toFixed(weiBalance, 18)
    );
    smokeTest(kdl, base, quote);
  }

  function smokeTest(GeometricKandel kdl, IERC20 base, IERC20 quote) internal view {
    require(base.balanceOf(address(kdl)) == 0, "smokeTest: fail 1");
    require(base.balanceOf(address(kdl.router())) == 0, "smokeTest: fail 2");
    require(kdl.reserveBalance(OfferType.Ask) == 0, "smokeTest: fail 3");
    require(quote.balanceOf(address(kdl)) == 0, "smokeTest: fail 4");
    require(quote.balanceOf(address(kdl.router())) == 0, "smokeTest: fail 5");
    require(kdl.reserveBalance(OfferType.Bid) == 0, "smokeTest: fail 6");
    require(kdl.MGV().balanceOf(address(kdl)) == 0, "smokeTest: fail 7");
    prettyLog("Simulation says all funds will be withdrawn");
  }
}
