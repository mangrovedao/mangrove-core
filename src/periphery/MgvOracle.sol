// SPDX-License-Identifier:	AGPL-3.0

// MgvOracle.sol

// Copyright (C) 2021 Giry SAS.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity ^0.8.10;
pragma abicoder v2;
import "../MgvLib.sol";

/* The purpose of the Oracle contract is to act as a gas price and density
 * oracle for the Mangrove. It bridges to an external oracle, and allows
 * a given sender to update the gas price and density which the oracle
 * reports to Mangrove. */
contract MgvOracle is IMgvMonitor {
  event SetGasprice(uint gasPrice);
  event SetDensity(uint density);

  address governance;
  address mutator;

  uint lastReceivedGasPrice;
  uint lastReceivedDensity;

  constructor(address _governance, address _initialMutator) {
    governance = _governance;
    mutator = _initialMutator;

    /* Set initial density from the MgvOracle to let Mangrove use its internal density by default.

      Mangrove will reject densities from the Monitor that don't fit in 32 bits and use its internal density instead, so setting this contract's density to `type(uint).max` is a way to let Mangrove deal with density on its own. */
    lastReceivedDensity = type(uint).max;
  }

  /* ## `authOnly` check */
  // NOTE: Should use standard auth method, instead of this copy from MgvGovernable

  function authOnly() internal view {
    require(
      msg.sender == governance ||
        msg.sender == address(this) ||
        governance == address(0),
      "MgvOracle/unauthorized"
    );
  }

  function notifySuccess(MgvLib.SingleOrder calldata sor, address taker)
    external
    override
  {
    // Do nothing
  }

  function notifyFail(MgvLib.SingleOrder calldata sor, address taker)
    external
    override
  {
    // Do nothing
  }

  function setMutator(address _mutator) external {
    authOnly();

    mutator = _mutator;
  }

  function setGasPrice(uint gasPrice) external {
    // governance or mutator are allowed to update the gasprice
    require(
      msg.sender == governance || msg.sender == mutator,
      "MgvOracle/unauthorized"
    );

    lastReceivedGasPrice = gasPrice;
    emit SetGasprice(gasPrice);
  }

  function setDensity(uint density) external {
    // governance or mutator are allowed to update the density
    require(
      msg.sender == governance || msg.sender == mutator,
      "MgvOracle/unauthorized"
    );

    lastReceivedDensity = density;
    emit SetDensity(density);
  }

  function read(
    address, /*outbound_tkn*/
    address /*inbound_tkn*/
  ) external view override returns (uint gasprice, uint density) {
    return (lastReceivedGasPrice, lastReceivedDensity);
  }
}
