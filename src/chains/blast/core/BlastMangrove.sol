// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {Mangrove} from "../../../core/Mangrove.sol";
import {IBlastPoints} from "../interfaces/IBlastPoints.sol";
import {IBlastMangrove} from "../IBlastMangrove.sol";
import {BlastLib} from "../lib/BlastLib.sol";

/// @title BlastMangrove
/// @author Mangrove
/// @notice A contract that inherits Mangrove and BlastGasAndYieldClaimable
/// @dev if a change in governance is needed, then call the blast contract to change the governance
/// * finally change the admin
contract BlastMangrove is Mangrove, IBlastPoints {
  constructor(address governance, uint gasprice, uint gasmax) Mangrove(governance, gasprice, gasmax) {
    BlastLib.BLAST.configureGovernor(governance);
  }

  function blastPointsAdmin() external view override returns (address) {
    return IBlastMangrove(payable(address(this))).governance();
  }
}
