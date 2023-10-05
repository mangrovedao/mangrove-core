// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import "@mgv/src/core/MgvLib.sol";

/* The purpose of the Oracle contract is to act as a gas price and density
 * oracle for Mangrove. It bridges to an external oracle, and allows
 * a given sender to update the gas price and density which the oracle
 * reports to Mangrove. */
contract MgvOracle is IMgvMonitor {
  event SetGasprice(uint gasPrice);
  event SetDensity96X32(uint density96X32);

  address governance;
  address mutator;

  uint lastReceivedGasPrice;
  Density lastReceivedDensity;

  constructor(address governance_, address initialMutator_, uint initialGasPrice_) {
    governance = governance_;
    mutator = initialMutator_;

    lastReceivedGasPrice = initialGasPrice_;
    /* Set initial density from the MgvOracle to let Mangrove use its internal density by default.

      Mangrove will reject densities from the Monitor that are not 9-bit floats and use its internal density instead, so setting this contract's density to `type(uint).max` is a way to let Mangrove deal with density on its own. */
    lastReceivedDensity = Density.wrap(type(uint).max);
  }

  /* ## `authOnly` check */
  // NOTE: Should use standard auth method, instead of this copy from MgvGovernable

  function authOnly() internal view {
    require(
      msg.sender == governance || msg.sender == address(this) || governance == address(0), "MgvOracle/unauthorized"
    );
  }

  function notifySuccess(MgvLib.SingleOrder calldata sor, address taker) external override {
    // Do nothing
  }

  function notifyFail(MgvLib.SingleOrder calldata sor, address taker) external override {
    // Do nothing
  }

  function setGovernance(address governance_) external {
    authOnly();

    governance = governance_;
  }

  function setMutator(address mutator_) external {
    authOnly();

    mutator = mutator_;
  }

  function setGasPrice(uint gasPrice) external {
    // governance or mutator are allowed to update the gasprice
    require(msg.sender == governance || msg.sender == mutator, "MgvOracle/unauthorized");

    lastReceivedGasPrice = gasPrice;
    emit SetGasprice(gasPrice);
  }

  /* Density is given as a 96.32 fixed point number. It will be stored as a 9-bit float and be approximated towards 0. The maximum error is 20%. See `DensityLib` for more information. */
  function setDensity96X32(uint density96X32) external {
    // governance or mutator are allowed to update the density
    require(msg.sender == governance || msg.sender == mutator, "MgvOracle/unauthorized");

    /* Checking the size of `density` is necessary to prevent overflow before storing density as a float. */
    require(DensityLib.checkDensity96X32(density96X32), "MgvOracle/config/density96X32/wrong");

    lastReceivedDensity = DensityLib.from96X32(density96X32);
    emit SetDensity96X32(density96X32);
  }

  function read(OLKey memory) external view override returns (uint gasprice, Density density) {
    return (lastReceivedGasPrice, lastReceivedDensity);
  }
}
