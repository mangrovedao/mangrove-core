// SPDX-License-Identifier:	BSD-2-Clause

// AaveKandelSeeder.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {MgvStructs} from "mgv_src/MgvLib.sol";
import {AaveKandel, AavePooledRouter} from "./AaveKandel.sol";
import {GeometricKandel} from "./abstract/GeometricKandel.sol";
import {AbstractKandelSeeder} from "./abstract/AbstractKandelSeeder.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";

///@title AaveKandel strat deployer.
///@notice This seeder deploys Kandel strats on demand and binds them to an AAVE router.
///@dev deployer of this contract will gain aave manager power on the AAVE router (power to claim rewards and enter/exit markets)
///@dev when deployer is a contract one must therefore make sure it is able to call the corresponding functions on the router
contract AaveKandelSeeder is AbstractKandelSeeder {
  AavePooledRouter public immutable AAVE_ROUTER;
  IMangrove public immutable MGV;
  uint public immutable AAVE_KANDEL_GASREQ;

  ///@notice constructor for `AaveKandelSeeder`. Initializes an `AavePooledRouter` with this seeder as manager.
  constructor(IMangrove mgv, address addressesProvider, uint routerGasreq, uint aaveKandelGasreq) {
    AavePooledRouter router = new AavePooledRouter(addressesProvider, routerGasreq);
    AAVE_ROUTER = router;
    MGV = mgv;
    AAVE_KANDEL_GASREQ = aaveKandelGasreq;
    router.setAaveManager(msg.sender);
  }

  ///@notice deploys a new Kandel contract for the given seed.
  ///@param seed the parameters for the Kandel strat
  ///@return kandel the Kandel contract.
  function sow(KandelSeed calldata seed) external override returns (GeometricKandel kandel) {
    // Seeder must set Kandel owner to an address that is controlled by `msg.sender` (msg.sender or Kandel's address for instance)
    // owner MUST not be freely chosen (it is immutable in Kandel) otherwise one would allow the newly deployed strat to pull from another's strat reserve
    // allowing owner to be modified by Kandel's admin would require approval from owner's address controller
    address owner = seed.liquiditySharing ? msg.sender : address(0);

    (, MgvStructs.LocalPacked local) = MGV.config(address(seed.base), address(seed.quote));
    require(local.active(), "KandelSeeder/inactiveMarket");

    AaveKandel aaveKandel = new AaveKandel(MGV, seed.base, seed.quote, AAVE_KANDEL_GASREQ, seed.gasprice, owner);
    // Allowing newly deployed Kandel to bind to the AaveRouter
    AAVE_ROUTER.bind(address(aaveKandel));
    // Setting AaveRouter as Kandel's router and activating router on BASE and QUOTE ERC20
    aaveKandel.initialize(AAVE_ROUTER);
    kandel = aaveKandel;
    emit NewAaveKandel(msg.sender, seed.base, seed.quote, address(kandel), owner);

    uint fullCompound = 10 ** kandel.PRECISION();
    kandel.setCompoundRates(fullCompound, fullCompound);
    kandel.setAdmin(msg.sender);
  }
}
