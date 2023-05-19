// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {Kandel} from "./Kandel.sol";
import {GeometricKandel} from "./abstract/GeometricKandel.sol";
import {AbstractKandelSeeder} from "./abstract/AbstractKandelSeeder.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";

///@title Kandel strat deployer.
contract KandelSeeder is AbstractKandelSeeder {
  ///@notice constructor for `KandelSeeder`.
  ///@param mgv The Mangrove deployment.
  ///@param kandelGasreq the gasreq to use for offers.
  constructor(IMangrove mgv, uint kandelGasreq) AbstractKandelSeeder(mgv, kandelGasreq) {}

  ///@inheritdoc AbstractKandelSeeder
  function _deployKandel(KandelSeed calldata seed) internal override returns (GeometricKandel kandel) {
    kandel = new Kandel(MGV, seed.base, seed.quote, KANDEL_GASREQ, seed.gasprice, address(0));
    emit NewKandel(msg.sender, seed.base, seed.quote, address(kandel));
  }
}
