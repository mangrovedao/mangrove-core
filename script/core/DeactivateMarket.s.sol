// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import "@mgv/src/periphery/MgvReader.sol";
import {UpdateMarket} from "@mgv/script/periphery/UpdateMarket.s.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import "@mgv/src/core/MgvLib.sol";

/* Deactivate a market (aka two mangrove offer lists) & update MgvReader. */
contract DeactivateMarket is Deployer {
  function run() public {
    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      reader: MgvReader(envAddressOrName("MGV_READER", "MgvReader")),
      market: Market({
        tkn0: envAddressOrName("TKN0"),
        tkn1: envAddressOrName("TKN1"),
        tickSpacing: vm.envUint("TICK_SPACING")
      })
    });
    outputDeployment();
  }

  function innerRun(IMangrove mgv, MgvReader reader, Market memory market) public {
    broadcast();
    mgv.deactivate(toOLKey(market));

    broadcast();
    mgv.deactivate(toOLKey(flipped(market)));

    (new UpdateMarket()).innerRun({market: market, reader: reader});

    smokeTest(reader, market);
  }

  function smokeTest(MgvReader reader, Market memory market) internal view {
    MarketConfig memory config = reader.marketConfig(market);
    require(!(config.config01.active || config.config10.active), "Market was not deactivated");
    require(!reader.isMarketOpen(market), "Reader state not updated");
  }
}
