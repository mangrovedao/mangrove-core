// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {AaveKandel, AavePooledRouter} from "./AaveKandel.sol";
import {GeometricKandel} from "./abstract/GeometricKandel.sol";
import {AbstractKandelSeeder} from "./abstract/AbstractKandelSeeder.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";

///@title AaveKandel strat deployer.
contract AaveKandelSeeder is AbstractKandelSeeder {
  ///@notice the Aave router.
  AavePooledRouter public immutable AAVE_ROUTER;

  ///@notice constructor for `AaveKandelSeeder`. Initializes an `AavePooledRouter` with this seeder as manager.
  ///@param mgv The Mangrove deployment.
  ///@param addressesProvider address of AAVE's address provider
  ///@param routerGasreq is the amount of gas that is required for the AavePooledRouter to be able to perform a `pull` and a `push`.
  ///@param aaveKandelGasreq the gasreq to use for offers besides the routerGasreq.
  constructor(IMangrove mgv, address addressesProvider, uint routerGasreq, uint aaveKandelGasreq)
    AbstractKandelSeeder(mgv, aaveKandelGasreq)
  {
    AavePooledRouter router = new AavePooledRouter(addressesProvider, routerGasreq);
    AAVE_ROUTER = router;
    router.setAaveManager(msg.sender);
  }

  ///@inheritdoc AbstractKandelSeeder
  function _deployKandel(KandelSeed calldata seed) internal override returns (GeometricKandel kandel) {
    // Seeder must set Kandel owner to an address that is controlled by `msg.sender` (msg.sender or Kandel's address for instance)
    // owner MUST not be freely chosen (it is immutable in Kandel) otherwise one would allow the newly deployed strat to pull from another's strat reserve
    // allowing owner to be modified by Kandel's admin would require approval from owner's address controller
    address owner = seed.liquiditySharing ? msg.sender : address(0);

    kandel = new AaveKandel(MGV, seed.base, seed.quote, KANDEL_GASREQ, seed.gasprice, owner);
    // Allowing newly deployed Kandel to bind to the AaveRouter
    AAVE_ROUTER.bind(address(kandel));
    // Setting AaveRouter as Kandel's router and activating router on BASE and QUOTE ERC20
    AaveKandel(payable(kandel)).initialize(AAVE_ROUTER);
    emit NewAaveKandel(msg.sender, seed.base, seed.quote, address(kandel), owner);
  }
}
