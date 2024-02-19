// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Mangrove} from "../../../core/Mangrove.sol";
import {BlastGasAndYieldClaimable} from "../utils/BlastGasAndYieldClaimable.sol";
import {BlastMgvAppendix} from "./BlastMgvAppendix.sol";

/// @title BlastMangrove
/// @author Mangrove
/// @notice A contract that inherits Mangrove and BlastGasAndYieldClaimable
/// @dev if a change in governance is needed, then call the blast contract to change the claimer
/// * Then call this contract to change the points admin with setPointsAdmin function
/// * finally change the admin
contract BlastMangrove is Mangrove, BlastGasAndYieldClaimable {
  constructor(address governance, uint gasprice, uint gasmax)
    Mangrove(governance, gasprice, gasmax)
    BlastGasAndYieldClaimable(governance)
  {}

  function deployAppendix() internal override returns (address) {
    return address(new BlastMgvAppendix());
  }
}
