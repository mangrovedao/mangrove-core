// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Mangrove} from "../../../core/Mangrove.sol";
import {IBlastPoints} from "../interfaces/IBlastPoints.sol";
import {IBlastMangrove} from "../IBlastMangrove.sol";
import {BlastLib} from "../lib/BlastLib.sol";
import {GasMode, YieldMode} from "../interfaces/IBlast.sol";

/// @title BlastMangrove
/// @author Mangrove
/// @notice A contract that inherits Mangrove and BlastGasAndYieldClaimable
/// @dev if a change in governance is needed, then call the blast contract to change the claimer
/// * Then call this contract to change the points admin with setPointsAdmin function
/// * finally change the admin
contract BlastMangrove is Mangrove, IBlastPoints {
  constructor(address governance, uint gasprice, uint gasmax) Mangrove(governance, gasprice, gasmax) {
    BlastLib.BLAST.configure(YieldMode.CLAIMABLE, GasMode.CLAIMABLE, governance);
  }

  function blastPointsAdmin() external view override returns (address) {
    return IBlastMangrove(payable(address(this))).governance();
  }
}
