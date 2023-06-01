// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";

import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";

import {UpdateMarket} from "mgv_script/periphery/UpdateMarket.s.sol";

import {IERC20} from "mgv_src/IERC20.sol";

/* Update TestToken markets in MgvReader */
contract MumbaiUpdateTestTokenMarketsInMgvReader is Deployer {
  function run() public {
    innerRun({
      reader: MgvReader(envAddressOrName("MGV_READER", "MgvReader")),
      wbtc: IERC20(fork.get("WBTC")),
      wmatic: IERC20(fork.get("WMATIC")),
      usdt: IERC20(fork.get("USDT"))
    });
    outputDeployment();
  }

  function innerRun(MgvReader reader, IERC20 wbtc, IERC20 wmatic, IERC20 usdt) public {
    (new UpdateMarket()).innerRun({tkn0: wbtc, tkn1: usdt, reader: reader});
    (new UpdateMarket()).innerRun({tkn0: wmatic, tkn1: usdt, reader: reader});
  }
}
