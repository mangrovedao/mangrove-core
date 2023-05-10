// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";
import "forge-std/console.sol";

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
    (address[2][] memory markets, MgvReader.MarketConfig[] memory configs) = previousReader.openMarkets();

    currentMangrove = Mangrove(payable(currentReader.MGV()));

    console.log("Enabling semibooks...");

    for (uint i = 0; i < markets.length; i++) {
      address tkn0 = markets[i][0];
      address tkn1 = markets[i][1];
      updateActivation(tkn0, tkn1, configs[i].config01);
      updateActivation(tkn1, tkn0, configs[i].config10);
      broadcast();
      currentReader.updateMarket(tkn0, tkn1);
    }
    console.log("...done.");
  }

  function updateActivation(address tknA, address tknB, MgvStructs.LocalUnpacked memory cAB) internal {
    if (cAB.active) {
      console.log(tknA, tknB);
      broadcast();
      currentMangrove.activate({
        outbound_tkn: tknA,
        inbound_tkn: tknB,
        fee: cAB.fee,
        density: cAB.density,
        offer_gasbase: cAB.offer_gasbase
      });
    }
  }
}
