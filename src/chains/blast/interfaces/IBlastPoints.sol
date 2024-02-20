// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

/// @title IBlastPoints
/// @notice Interface to implement blast points
interface IBlastPoints {
  /// @notice Get the points admin for blast
  /// @return The points admin address
  function blastPointsAdmin() external view returns (address);
}
