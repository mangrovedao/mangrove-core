// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import "@mgv/src/periphery/MgvReader.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";
import "@mgv/lib/Debug.sol";

/* Update market information on MgvReader.
   
  Calls the permisionless function updateMarket of MgvReader. Ensures that
  MgvReader knows the correct market state of the tkn0,tkn1,tickSpacing offer list on Mangrove.

  The token pair is not directed! You do not need to call it once with
  (tkn0,tkn1) then (tkn1,tkn0). Doing it once is fine.*/
contract UpdateMarket is Deployer {
  function run() public {
    innerRun({
      reader: MgvReader(envAddressOrName("MGV_READER", "MgvReader")),
      market: Market(envAddressOrName("TKN0"), envAddressOrName("TKN1"), vm.envUint("TICK_SPACING"))
    });
    outputDeployment();
  }

  function innerRun(MgvReader reader, Market memory market) public {
    console.log(
      "Updating Market on MgvReader.  tkn0: %s, tkn1: %s",
      vm.toString(market.tkn0),
      vm.toString(market.tkn1),
      vm.toString(market.tickSpacing)
    );
    logReaderState("[before script]", reader, market);

    broadcast();
    reader.updateMarket(market);

    logReaderState("[after  script]", reader, market);
  }

  function logReaderState(string memory intro, MgvReader reader, Market memory market) internal view {
    string memory open = reader.isMarketOpen(market) ? "open" : "closed";
    console.log("%s MgvReader sees market as: %s", intro, open);
  }
}
