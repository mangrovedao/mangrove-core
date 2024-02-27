// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IMangrove} from "../../IMangrove.sol";

/// @title IBlastMangrove
/// @notice Interface implemented by BlastMangrove.
interface IBlastMangrove is IMangrove {
  /// @notice Change the Blast governor.
  /// @param governor The new governor address.
  /// @dev Only Mangrove governance can call this function.
  /// @dev This ensures that Mangrove governance can always change the governor.
  function configureBlastGovernor(address governor) external;

  /// @notice Change the BlastPoints operator.
  /// @param operator The new operator address
  /// @dev Only Mangrove governance can call this function.
  /// @dev This ensures that Mangrove governance can always change the operator.
  function configureBlastPointsOperator(address operator) external;
}
