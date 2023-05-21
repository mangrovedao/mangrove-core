// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {GeometricKandel} from "./GeometricKandel.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";

///@title Abstract Kandel strat deployer.
///@notice This seeder deploys Kandel strats on demand and binds them to an AAVE router if needed.
///@dev deployer of this contract will gain aave manager power on the AAVE router (power to claim rewards and enter/exit markets)
///@dev when deployer is a contract one must therefore make sure it is able to call the corresponding functions on the router
abstract contract AbstractKandelSeeder {
  ///@notice The Mangrove deployment.
  IMangrove public immutable MGV;
  ///@notice the gasreq to use for offers.
  uint public immutable KANDEL_GASREQ;

  ///@notice constructor for `AbstractKandelSeeder`.
  ///@param mgv The Mangrove deployment.
  ///@param kandelGasreq the gasreq to use for offers
  constructor(IMangrove mgv, uint kandelGasreq) {
    MGV = mgv;
    KANDEL_GASREQ = kandelGasreq;
  }

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
  function sow(KandelSeed calldata seed) external returns (GeometricKandel kandel) {
    // Seeder must set Kandel owner to an address that is controlled by `msg.sender` (msg.sender or Kandel's address for instance)
    // owner MUST not be freely chosen (it is immutable in Kandel) otherwise one would allow the newly deployed strat to pull from another's strat reserve
    // allowing owner to be modified by Kandel's admin would require approval from owner's address controller

    (, MgvStructs.LocalPacked local) = MGV.config(address(seed.base), address(seed.quote));
    (, MgvStructs.LocalPacked local_) = MGV.config(address(seed.quote), address(seed.base));

    require(local.active() && local_.active(), "KandelSeeder/inactiveMarket");

    kandel = _deployKandel(seed);
    uint fullCompound = 10 ** kandel.PRECISION();
    kandel.setCompoundRates(fullCompound, fullCompound);
    kandel.setAdmin(msg.sender);
  }

  ///@notice deploys a new Kandel contract for the given seed.
  ///@param seed the parameters for the Kandel strat
  ///@return kandel the Kandel contract.
  function _deployKandel(KandelSeed calldata seed) internal virtual returns (GeometricKandel kandel);
}
