// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import "forge-std/console.sol";

/* Update market information on MgvReader.
   
  Calls the permisionless function updateMarket of MgvReader. Ensures that
  MgvReader knows the correct market state of the tkn0,tkn1 pair on Mangrove.

  The token pair is not directed! You do not need to call it once with
  (tkn0,tkn1) then (tkn1,tkn0). Doing it once is fine.*/
contract UpdateMarket is Deployer {
  function run() public {
    innerRun({
      reader: MgvReader(envAddressOrName("MGV_READER", "MgvReader")),
      tkn0: IERC20(envAddressOrName("TKN0")),
      tkn1: IERC20(envAddressOrName("TKN1"))
    });
    outputDeployment();
  }

  function innerRun(MgvReader reader, IERC20 tkn0, IERC20 tkn1) public {
    console.log(
      "Updating Market on MgvReader.  tkn0: %s, tkn1: %s", vm.toString(address(tkn0)), vm.toString(address(tkn1))
    );
    logReaderState("[before script]", reader, tkn0, tkn1);

    broadcast();
    reader.updateMarket(address(tkn0), address(tkn1));

    logReaderState("[after  script]", reader, tkn0, tkn1);
  }

  function logReaderState(string memory intro, MgvReader reader, IERC20 tkn0, IERC20 tkn1) internal view {
    string memory open = reader.isMarketOpen(address(tkn0), address(tkn1)) ? "open" : "closed";
    console.log("%s MgvReader sees market as: %s", intro, open);
  }
}
