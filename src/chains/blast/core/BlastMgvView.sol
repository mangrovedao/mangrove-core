// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {MgvView} from "../../../core/MgvView.sol";
import {IBlastPoints} from "../interfaces/IBlastPoints.sol";

/// @title BlastMgvView
/// @notice A contract that inherits MgvView
/// @dev This contract is used to get the points admin for blast
contract BlastMgvView is MgvView, IBlastPoints {
  function blastPointsAdmin() external view override returns (address) {
    return _governance;
  }
}
