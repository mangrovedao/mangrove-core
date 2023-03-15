// SPDX-License-Identifier:	BSD-2-Clause

// AaveKandelSeeder.sol

// Copyright (c) 2023 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {AaveKandel, AavePooledRouter} from "./AaveKandel.sol";
import {GeometricKandel} from "./abstract/GeometricKandel.sol";
import {AbstractKandelSeeder} from "./abstract/AbstractKandelSeeder.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";

///@title AaveKandel strat deployer.
contract AaveKandelSeeder is AbstractKandelSeeder {
  AavePooledRouter public immutable AAVE_ROUTER;

  ///@notice constructor for `AaveKandelSeeder`. Initializes an `AavePooledRouter` with this seeder as manager.
  constructor(IMangrove mgv, address addressesProvider) AbstractKandelSeeder(mgv) {
    AavePooledRouter router = new AavePooledRouter(addressesProvider, 500_000);
    AAVE_ROUTER = router;
    router.setAaveManager(msg.sender);
  }

  ///@inheritdoc AbstractKandelSeeder
  function _deployKandel(KandelSeed calldata seed) internal override returns (GeometricKandel kandel) {
    // Seeder must set Kandel owner to an address that is controlled by `msg.sender` (msg.sender or Kandel's address for instance)
    // owner MUST not be freely chosen (it is immutable in Kandel) otherwise one would allow the newly deployed strat to pull from another's strat reserve
    // allowing owner to be modified by Kandel's admin would require approval from owner's address controller
    address owner = seed.liquiditySharing ? msg.sender : address(0);

    kandel = new AaveKandel(MGV, seed.base, seed.quote, 160_000, seed.gasprice, owner, 95_000, 95_000);
    // Allowing newly deployed Kandel to bind to the AaveRouter
    AAVE_ROUTER.bind(address(kandel));
    // Setting AaveRouter as Kandel's router and activating router on BASE and QUOTE ERC20
    AaveKandel(payable(kandel)).initialize(AAVE_ROUTER);
    emit NewAaveKandel(msg.sender, seed.base, seed.quote, address(kandel), owner);
  }
}
