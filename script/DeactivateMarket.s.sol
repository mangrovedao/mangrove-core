// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MgvOracle} from "mgv_src/periphery/MgvOracle.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";
import {ERC20} from "mgv_src/toy/ERC20.sol";

contract DeactivateMarket is Deployer {
  function run() public {
    innerRun({tkn1: envAddressOrName("TKN1"), tkn2: envAddressOrName("TKN2")});
  }

  function innerRun(address tkn1, address tkn2) public {
    IMangrove mgv = IMangrove(fork.get("Mangrove"));
    MgvReader mgvr = MgvReader(fork.get("MgvReader"));
    require(mgv.governance() == broadcaster(), "Only governance can call");
    broadcast();
    mgv.deactivate(tkn1, tkn2);

    broadcast();
    mgv.deactivate(tkn2, tkn1);

    broadcast();
    mgvr.updateMarket(tkn1, tkn2);

    smokeTest(mgv, mgvr, tkn1, tkn2);
  }

  function smokeTest(IMangrove mgv, MgvReader mgvr, address tkn1, address tkn2) internal view {
    (, MgvStructs.LocalPacked local12) = mgv.config(tkn1, tkn2);
    (, MgvStructs.LocalPacked local21) = mgv.config(tkn2, tkn1);
    require(!(local12.active() || local21.active()), "Market was not deactivated");
    require(!mgvr.isMarketOpen(tkn1, tkn2), "Reader state not updated");
  }
}
