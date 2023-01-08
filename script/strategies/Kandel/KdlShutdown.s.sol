// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {
  ExplicitKandel as Kandel,
  AbstractKandel,
  IERC20,
  IMangrove,
  MgvStructs
} from "mgv_src/strategies/offer_maker/market_making/kandel/ExplicitKandel.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveTest, Test} from "mgv_test/lib/MangroveTest.sol";

/**
 * @notice deploys a Kandel instance on a given market
 */

contract KdlShutDown is Deployer {
  Kandel public current;

  function run() public {
    innerRun({kdl: Kandel(envAddressOrName("KANDEL"))});
  }

  function innerRun(Kandel kdl) public {
    uint N = kdl.NSLOTS();
    prettyLog("Retracting offers from Mangrove...");
    broadcast();
    uint retracted = kdl.retractOffers(0, N);

    uint balWei = kdl.MGV().balanceOf(address(kdl));
    broadcast();
    kdl.withdrawFromMangrove(balWei, payable(msg.sender));
    console.log("%s native tokens redeemed", toUnit(retracted + balWei, 18));

    IERC20 BASE = kdl.BASE();
    IERC20 QUOTE = kdl.QUOTE();

    uint baseBalance = BASE.balanceOf(address(kdl));
    uint quoteBalance = QUOTE.balanceOf(address(kdl));

    prettyLog("Withdrawing funds from Kandel...");
    broadcast();
    kdl.withdrawFunds(AbstractKandel.OrderType.Bid, quoteBalance, msg.sender);

    broadcast();
    kdl.withdrawFunds(AbstractKandel.OrderType.Ask, baseBalance, msg.sender);

    console.log(
      "Withdrawn %s base and %s quote tokens",
      toUnit(baseBalance, BASE.decimals()),
      toUnit(quoteBalance, QUOTE.decimals())
    );
  }
}
