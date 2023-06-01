// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";

import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";

import {DeactivateMarket} from "mgv_script/core/DeactivateMarket.s.sol";

import {IERC20} from "mgv_src/IERC20.sol";

/* Deactivate the AAVE token markets */
contract MumbaiDeactivateAaveMarkets is Deployer {
  function run() public {
    innerRun({
      mgv: Mangrove(envAddressOrName("MGV", "Mangrove")),
      reader: MgvReader(envAddressOrName("MGV_READER", "MgvReader")),
      weth: IERC20(fork.get("WETH")),
      usdc: IERC20(fork.get("USDC")),
      dai: IERC20(fork.get("DAI"))
    });
    outputDeployment();
  }

  function innerRun(Mangrove mgv, MgvReader reader, IERC20 weth, IERC20 usdc, IERC20 dai) public {
    (new DeactivateMarket()).innerRun({mgv: mgv, tkn0: weth, tkn1: usdc, reader: reader});
    (new DeactivateMarket()).innerRun({mgv: mgv, tkn0: weth, tkn1: dai, reader: reader});
    (new DeactivateMarket()).innerRun({mgv: mgv, tkn0: dai, tkn1: usdc, reader: reader});
  }
}
