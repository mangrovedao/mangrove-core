// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {UpdateMarket} from "mgv_script/periphery/UpdateMarket.s.sol";

/* Deactivate a market (aka two mangrove semibooks) & update MgvReader. */
contract DeactivateMarket is Deployer {
  function run() public {
    innerRun({tkn0: envAddressOrName("TKN0"), tkn1: envAddressOrName("TKN1")});
    outputDeployment();
  }

  function innerRun(address tkn0, address tkn1) public {
    Mangrove mgv = Mangrove(fork.get("Mangrove"));
    MgvReader reader = MgvReader(fork.get("MgvReader"));

    broadcast();
    mgv.deactivate(tkn0, tkn1);

    broadcast();
    mgv.deactivate(tkn1, tkn0);

    (new UpdateMarket()).innerRun({tkn0: tkn0, tkn1: tkn1, mgvReaderAddress: address(reader)});

    smokeTest(reader, tkn0, tkn1);
  }

  function smokeTest(MgvReader reader, address tkn0, address tkn1) internal view {
    MgvReader.MarketConfig memory config = reader.marketConfig(tkn0, tkn1);
    require(!(config.config01.active || config.config10.active), "Market was not deactivated");
    require(!reader.isMarketOpen(tkn0, tkn1), "Reader state not updated");
  }
}
