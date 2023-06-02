// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";

import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";

import {DeactivateMarket} from "mgv_script/core/DeactivateMarket.s.sol";

import {IERC20} from "mgv_src/IERC20.sol";

/* Deactivate the TestToken token markets */
contract MumbaiDeactivateTestTokenMarkets is Deployer {
  function run() public {
    innerRun({
      mgv: Mangrove(envAddressOrName("MGV", "Mangrove")),
      reader: MgvReader(envAddressOrName("MGV_READER", "MgvReader")),
      wbtc: IERC20(fork.get("WBTC")),
      wmatic: IERC20(fork.get("WMATIC")),
      usdt: IERC20(fork.get("USDT"))
    });
    outputDeployment();
  }

  function innerRun(Mangrove mgv, MgvReader reader, IERC20 wbtc, IERC20 wmatic, IERC20 usdt) public {
    //(new DeactivateMarket()).innerRun({mgv: mgv, tkn0: wbtc, tkn1: usdt, reader: reader});
    (new DeactivateMarket()).innerRun({mgv: mgv, tkn0: wmatic, tkn1: usdt, reader: reader});
  }
}
