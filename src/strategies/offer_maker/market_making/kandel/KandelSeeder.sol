// SPDX-License-Identifier:	BSD-2-Clause

// KandelDeployer.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {MgvStructs} from "mgv_src/MgvLib.sol";
import {Kandel} from "./Kandel.sol";
import {AaveKandel, AavePooledRouter} from "./AaveKandel.sol";
import {GeometricKandel} from "./abstract/GeometricKandel.sol";
import {OfferType} from "./abstract/Trade.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";

contract KandelSeeder {
  AavePooledRouter public immutable AAVE_ROUTER;
  IMangrove public immutable MGV;
  uint public immutable AAVE_KANDEL_GASREQ;
  uint public immutable KANDEL_GASREQ;

  constructor(IMangrove mgv, address addressesProvider_, uint routerGasreq, uint aaveKandelGasreq, uint kandelGasreq) {
    AAVE_ROUTER = new AavePooledRouter(addressesProvider_, routerGasreq);
    MGV = mgv;
    AAVE_KANDEL_GASREQ = aaveKandelGasreq;
    KANDEL_GASREQ = kandelGasreq;
  }

  ///@notice Kandel deployment parameters
  ///@param base ERC20 of Kandel's market
  ///@param quote ERC20 of Kandel's market
  ///@param gasprice one wants to use for Kandel's provision
  ///@param onAave whether AaveKandel should be deployed instead of Kandel
  ///@param compoundRateBase amount (in bp) of incoming base tokens that should be automatically compounded
  ///@param compoundRateQuote amount (in bp) of incoming quote tokens that should be automatically compounded
  ///@param liquiditySharing if true, `msg.sender` will be used to identify the shares of the deployed Kandel strat. If msg.sender deploys several instances, reserve of the strats will be shared.
  struct KandelSeed {
    IERC20 base;
    IERC20 quote;
    uint gasprice;
    bool onAave;
    uint compoundRateBase;
    uint compoundRateQuote;
    bool liquiditySharing;
  }

  function sow(KandelSeed calldata seed) external returns (GeometricKandel kdl) {
    // Seeder must set Kandel owner to an address that is controlled by `msg.sender` (msg.sender or Kandel's address for instance)
    // owner MUST not be freely chosen (it is immutable in Kandel) otherwise one would allow the newly deployed strat to pull from another's strat reserve
    // allowing owner to be modified by Kandel's admin would require approval from owner's address controller
    address owner = seed.liquiditySharing ? msg.sender : address(0);

    (, MgvStructs.LocalPacked local) = MGV.config(address(seed.base), address(seed.quote));
    require(local.active(), "KandelSeeder/inactiveMarket");

    if (seed.onAave) {
      AaveKandel aaveKdl = new AaveKandel(MGV, seed.base, seed.quote, AAVE_KANDEL_GASREQ, seed.gasprice, owner);
      // Allowing newly deployed Kandel to bind to the AaveRouter
      AAVE_ROUTER.bind(address(aaveKdl));
      // Setting AaveRouter as Kandel's router and activating router on BASE and QUOTE ERC20
      aaveKdl.initialize(AAVE_ROUTER);
      kdl = aaveKdl;
    } else {
      kdl = new Kandel(MGV, seed.base, seed.quote, AAVE_KANDEL_GASREQ, seed.gasprice, owner);
    }
    kdl.setCompoundRates(seed.compoundRateBase, seed.compoundRateQuote);
    kdl.setAdmin(msg.sender);
  }
}
