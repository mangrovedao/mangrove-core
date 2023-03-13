// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import "forge-std/console.sol";

/* Update market information on MgvReader.
   
  Calls the permisionless function updateMarket of MgvReader. Ensures that
  MgvReader knows the correct market state of the tkn0,tkn1 pair on Mangrove.

  The token pair is not directed! You do not need to call it once with
  (tkn0,tkn1) then (tkn1,tkn0). Doing it once is fine.*/
contract UpdateMarket is Deployer {
  MgvReader reader;

  function run() public {
    innerRun({
      tkn0: envAddressOrName("TKN0"),
      tkn1: envAddressOrName("TKN1"),
      mgvReaderAddress: payable(envHas("MGV_READER") ? vm.envAddress("MGV_READER") : fork.get("MgvReader"))
    });
    outputDeployment();
  }

  function innerRun(address tkn0, address tkn1, address mgvReaderAddress) public {
    reader = MgvReader(mgvReaderAddress);

    console.log("Updating Market on MgvReader.  tkn0: %s, tkn1: %s", vm.toString(tkn0), vm.toString(tkn1));
    logReaderState("[before script]", tkn0, tkn1);

    broadcast();
    reader.updateMarket(tkn0, tkn1);

    logReaderState("[after  script]", tkn0, tkn1);
  }

  function logReaderState(string memory intro, address tkn0, address tkn1) internal view {
    string memory open = reader.isMarketOpen(tkn0, tkn1) ? "open" : "closed";
    console.log("%s MgvReader sees market as: %s", intro, open);
  }
}
