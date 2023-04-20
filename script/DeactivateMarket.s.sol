// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {UpdateMarket} from "mgv_script/periphery/UpdateMarket.s.sol";
import {IERC20} from "mgv_src/IERC20.sol";


/* Deactivate a market (aka two mangrove semibooks) & update MgvReader. */
contract DeactivateMarket is Deployer {
  function run() public {
    innerRun({
      mgv: Mangrove(envAddressOrName("MGV", "Mangrove")),
      reader: MgvReader(envAddressOrName("MGV_READER", "MgvReader")),
      tkn0: IERC20(envAddressOrName("TKN0")),
      tkn1: IERC20(envAddressOrName("TKN1"))
    });
    outputDeployment();
  }

  function innerRun(Mangrove mgv, MgvReader reader, IERC20 tkn0, IERC20 tkn1) public {
    broadcast();
    mgv.deactivate(address(tkn0), address(tkn1));

    broadcast();
    mgv.deactivate(address(tkn1), address(tkn0));

    (new UpdateMarket()).innerRun({tkn0: tkn0, tkn1: tkn1, reader: reader});

    smokeTest(reader, tkn0, tkn1);
  }

  function smokeTest(MgvReader reader, IERC20 tkn0, IERC20 tkn1) internal view {
    MgvReader.MarketConfig memory config = reader.marketConfig(address(tkn0), address(tkn1));
    require(!(config.config01.active || config.config10.active), "Market was not deactivated");
    require(!reader.isMarketOpen(address(tkn0), address(tkn1)), "Reader state not updated");
  }
}
