// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import "mgv_src/MgvLib.sol";

/* The purpose of the Oracle contract is to act as a gas price and density
 * oracle for Mangrove. It bridges to an external oracle, and allows
 * a given sender to update the gas price and density which the oracle
 * reports to Mangrove. */
contract MgvOracle is IMgvMonitor {
  event SetGasprice(uint gasPrice);
  event SetDensity(uint density);

  address governance;
  address mutator;

  uint lastReceivedGasPrice;
  uint lastReceivedDensity;

  constructor(address governance_, address initialMutator_) {
    governance = governance_;
    mutator = initialMutator_;

    /* Set initial density from the MgvOracle to let Mangrove use its internal density by default.

      Mangrove will reject densities from the Monitor that don't fit in 32 bits and use its internal density instead, so setting this contract's density to `type(uint).max` is a way to let Mangrove deal with density on its own. */
    lastReceivedDensity = type(uint).max;
  }

  /* ## authentication checks */
  // NOTE: Should use standard auth method
  function isGov() internal view returns (bool) {
    return msg.sender == governance || msg.sender == address(this) || governance == address(0);
  }

  // Only allow governance or self (or anyone if gov is not set)
  function authOnly() internal view {
    require(isGov(), "MgvOracle/unauthorized");
  }

  // Only allow governance or the mutator
  function authOrMutatorOnly() internal view {
    require(msg.sender == mutator || isGov(), "MgvOracle/unauthorized");
  }

  function notifySuccess(MgvLib.SingleOrder calldata sor, address taker) external override {
    // Do nothing
  }

  function notifyFail(MgvLib.SingleOrder calldata sor, address taker) external override {
    // Do nothing
  }

  function setMutator(address mutator_) external {
    authOnly();

    mutator = mutator_;
  }

  function setGasPrice(uint gasPrice) external virtual {
    authOrMutatorOnly();

    lastReceivedGasPrice = gasPrice;
    emit SetGasprice(gasPrice);
  }

  function setDensity(uint density) external {
    authOrMutatorOnly();

    lastReceivedDensity = density;
    emit SetDensity(density);
  }

  function read(address, /*outbound_tkn*/ address /*inbound_tkn*/ )
    external
    view
    virtual
    override
    returns (uint gasprice, uint density)
  {
    return (lastReceivedGasPrice, lastReceivedDensity);
  }
}
