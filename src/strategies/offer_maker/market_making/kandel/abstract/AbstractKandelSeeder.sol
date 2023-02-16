// SPDX-License-Identifier:	BSD-2-Clause

// AbstractKandelSeeder.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {GeometricKandel} from "./GeometricKandel.sol";
import {IERC20} from "mgv_src/IERC20.sol";

///@title Abstract Kandel strat deployer.
///@notice This seeder deploys Kandel strats on demand and binds them to an AAVE router if needed.
///@dev deployer of this contract will gain aave manager power on the AAVE router (power to claim rewards and enter/exit markets)
///@dev when deployer is a contract one must therefore make sure it is able to call the corresponding functions on the router
abstract contract AbstractKandelSeeder {
  ///@notice a new Kandel with pooled AAVE router has been deployed.
  ///@param owner the owner of the strat.
  ///@param base the base token.
  ///@param quote the quote token.
  ///@param aaveKandel the address of the deployed strat.
  ///@param reserveId the reserve identifier used for the router.
  event NewAaveKandel(
    address indexed owner, IERC20 indexed base, IERC20 indexed quote, address aaveKandel, address reserveId
  );

  ///@notice a new Kandel has been deployed.
  ///@param owner the owner of the strat.
  ///@param base the base token.
  ///@param quote the quote token.
  ///@param kandel the address of the deployed strat.
  event NewKandel(address indexed owner, IERC20 indexed base, IERC20 indexed quote, address kandel);

  ///@notice Kandel deployment parameters
  ///@param base ERC20 of Kandel's market
  ///@param quote ERC20 of Kandel's market
  ///@param gasprice one wants to use for Kandel's provision
  ///@param liquiditySharing if true, `msg.sender` will be used to identify the shares of the deployed Kandel strat. If msg.sender deploys several instances, reserve of the strats will be shared, but this will require a transfer from router to maker contract for each taken offer, since we cannot transfer the full amount to the first maker contract hit in a market order in case later maker contracts need the funds. Still, only a single AAVE redeem will take place.
  struct KandelSeed {
    IERC20 base;
    IERC20 quote;
    uint gasprice;
    bool liquiditySharing;
  }

  ///@notice deploys a new Kandel contract for the given seed.
  ///@param seed the parameters for the Kandel strat
  ///@return kandel the Kandel contract.
  function sow(KandelSeed calldata seed) external virtual returns (GeometricKandel kandel);
}
