// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {BaseBlast} from "./BaseBlast.sol";
import {GasMode, YieldMode} from "../interfaces/IBlast.sol";

/// @title BlastGasAndYieldClaimable
/// @author Mangrove
/// @notice A contract that inherits BaseBlast
/// @dev sets up the points and yield configuration for the contract
contract BlastGasAndYieldClaimable is BaseBlast {
  /// @notice Construct the BlastGasAndYieldClaimable contract
  /// @param governor The address of the governor
  constructor(address governor) {
    BLAST.configure(YieldMode.CLAIMABLE, GasMode.CLAIMABLE, governor);
  }
}
