// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import "mgv_src/periphery/MgvReader.sol";
import {UpdateMarket} from "mgv_script/periphery/UpdateMarket.s.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {OL} from "mgv_src/MgvLib.sol";

/* Deactivate a market (aka two mangrove semibooks) & update MgvReader. */
contract DeactivateMarket is Deployer {
  function run() public {
    innerRun({
      mgv: Mangrove(envAddressOrName("MGV", "Mangrove")),
      reader: MgvReader(envAddressOrName("MGV_READER", "MgvReader")),
      market: Market({tkn0: envAddressOrName("TKN0"), tkn1: envAddressOrName("TKN1"), tickScale: vm.envUint("TICKSCALE")})
    });
    outputDeployment();
  }

  function innerRun(Mangrove mgv, MgvReader reader, Market memory market) public {
    broadcast();
    mgv.deactivate(OL(market.tkn0, market.tkn1, market.tickScale));

    broadcast();
    mgv.deactivate(OL(market.tkn1, market.tkn0, market.tickScale));

    (new UpdateMarket()).innerRun({market: market, reader: reader});

    smokeTest(reader, market);
  }

  function smokeTest(MgvReader reader, Market memory market) internal view {
    MarketConfig memory config = reader.marketConfig(market);
    require(!(config.config01.active || config.config10.active), "Market was not deactivated");
    require(!reader.isMarketOpen(market), "Reader state not updated");
  }
}
