// SPDX-License-Identifier:	AGPL-3.0

// MgvOracle.sol

// Copyright (C) 2021 ADDMA.
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

import "mgv_src/MgvLib.sol";
import {MgvOracle} from "./MgvOracle.sol";

/* This Oracle uses EIP 1559 and the BASEFEE opcode to automate gasprice setting for Mangrove. It returns a gasprice of the form `current block's basefee + last received priority fee`. The priority fee can be adjusted by calling `setPriorityFee()`; the fee used in the transaction itself will be picked up.
 * To use it, you should point Mangrove to a MgvOracle1559 instance, and `setUseOracle(true)` on Mangrove.
 * You should monitor the chain's priority fee and make sure this oracle is up to date.
 */
contract MgvOracle1559 is MgvOracle {
  uint lastReceivedPriorityFee = txPriorityFee();

  // returned gas price will be multiplied by the given amount, in basis points.
  uint constant ONE_IN_BP = 10_000;
  uint lastReceivedGasScaling = ONE_IN_BP; // initial scaling factor is 1

  constructor(address governance, address initialMutator) MgvOracle(governance, initialMutator) {}

  function setGasPrice(uint) external pure override {
    revert("MgvOracle1559/noSetGasPrice");
  }

  // Update priority fee using this tx's prio fee
  function updatePriorityFee() external {
    setPriorityFee(txPriorityFee());
  }

  // Update priority fee to an arbitrary value
  function setPriorityFee(uint priorityFee) public {
    authOrMutatorOnly();
    lastReceivedPriorityFee = priorityFee;
  }

  function txPriorityFee() internal view returns (uint) {
    return tx.gasprice - block.basefee;
  }

  // Update gas scaling factor
  function setGasScaling(uint gasScaling) external {
    authOrMutatorOnly();
    lastReceivedGasScaling = gasScaling;
  }

  // You must make sure that the chosen priorityFee and gasScaling cannot trigger overflow when calling the read function. Otherwise, a Mangrove with useOracle set to true will be locked.
  function read(address, /*outbound_tkn*/ address /*inbound_tkn*/ )
    external
    view
    override
    returns (uint gasprice, uint density)
  {
    density = lastReceivedDensity;
    gasprice = (block.basefee + lastReceivedPriorityFee) * lastReceivedGasScaling / ONE_IN_BP;
  }
}
