// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {UpdateMarket} from "mgv_script/periphery/UpdateMarket.s.sol";
import {IERC20} from "mgv_src/IERC20.sol";

/* Deactivate a market (aka two mangrove semibooks) & update MgvReader. */
contract DeactivateMarket is Deployer {
  uint constant DEFAULT_TICKSCALE = 1;

  function run() public {
    innerRun({
      mgv: Mangrove(envAddressOrName("MGV", "Mangrove")),
      reader: MgvReader(envAddressOrName("MGV_READER", "MgvReader")),
      tkn0: IERC20(envAddressOrName("TKN0")),
      tkn1: IERC20(envAddressOrName("TKN1")),
      tickScale: DEFAULT_TICKSCALE
    });
    outputDeployment();
  }

  function innerRun(Mangrove mgv, MgvReader reader, IERC20 tkn0, IERC20 tkn1, uint tickScale) public {
    broadcast();
    mgv.deactivate(address(tkn0), address(tkn1), tickScale);

    broadcast();
    mgv.deactivate(address(tkn1), address(tkn0), tickScale);

    (new UpdateMarket()).innerRun({tkn0: tkn0, tkn1: tkn1, tickScale: DEFAULT_TICKSCALE, reader: reader});

    smokeTest(reader, tkn0, tkn1, tickScale);
  }

  function smokeTest(MgvReader reader, IERC20 tkn0, IERC20 tkn1, uint tickScale) internal view {
    MgvReader.MarketConfig memory config = reader.marketConfig(address(tkn0), address(tkn1), tickScale);
    require(!(config.config01.active || config.config10.active), "Market was not deactivated");
    require(!reader.isMarketOpen(address(tkn0), address(tkn1), tickScale), "Reader state not updated");
  }
}
