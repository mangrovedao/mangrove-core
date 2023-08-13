// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import "mgv_src/periphery/MgvReader.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MgvStructs, OL} from "mgv_src/MgvLib.sol";

/* 
Given two instances of MgvReader (previousReader and currentReader), copy the
config of every open semibook on previousReader's Mangrove (according to
previousReader's internal state) to currentReader's Mangrove.

It will never close semibooks.*/
contract CopyOpenSemibooks is Deployer {
  Mangrove currentMangrove;

  function run() public {
    innerRun({
      previousReader: MgvReader(envAddressOrName("PREVIOUS_READER")),
      currentReader: MgvReader(envAddressOrName("CURRENT_READER"))
    });
    outputDeployment();
  }

  function innerRun(MgvReader previousReader, MgvReader currentReader) public {
    console.log("Previous reader:", address(previousReader));
    console.log("Current reader: ", address(currentReader));
    (Market[] memory markets, MarketConfig[] memory configs) = previousReader.openMarkets();

    currentMangrove = Mangrove(payable(currentReader.MGV()));

    console.log("Enabling semibooks...");

    for (uint i = 0; i < markets.length; i++) {
      updateActivation(toOL(markets[i]), configs[i].config01);
      updateActivation(toOL(flipped(markets[i])), configs[i].config10);
      broadcast();
      currentReader.updateMarket(markets[i]);
    }
    console.log("...done.");
  }

  function updateActivation(OL memory ol, MgvStructs.LocalUnpacked memory cAB) internal {
    if (cAB.active) {
      console.log(ol.outbound, ol.inbound);
      broadcast();
      currentMangrove.activate({
        ol: ol,
        fee: cAB.fee,
        densityFixed: cAB.density.toFixed(),
        offer_gasbase: cAB.offer_gasbase()
      });
    }
  }
}
