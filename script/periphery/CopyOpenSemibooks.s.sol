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
      address tkn0 = markets[i].tkn0;
      address tkn1 = markets[i].tkn1;
      uint tickScale = markets[i].tickScale;
      updateActivation(tkn0, tkn1, tickScale, configs[i].config01);
      updateActivation(tkn1, tkn0, tickScale, configs[i].config10);
      broadcast();
      currentReader.updateMarket(markets[i]);
    }
    console.log("...done.");
  }

  function updateActivation(address tknA, address tknB, uint tickScale, MgvStructs.LocalUnpacked memory cAB) internal {
    if (cAB.active) {
      console.log(tknA, tknB);
      broadcast();
      currentMangrove.activate({
        ol: OL(tknA, tknB, tickScale),
        fee: cAB.fee,
        densityFixed: cAB.density.toFixed(),
        offer_gasbase: cAB.offer_gasbase()
      });
    }
  }
}
