// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {BaseBlast} from "./BaseBlast.sol";
import "@mgv/src/interfaces/IBlast.sol";
import "@mgv/src/interfaces/IBlastPoints.sol";

contract BlastGasAndYieldClaimable is BaseBlast, IBlastPoints {
  address public governor;

  constructor(address governor_) {
    governor = governor_;

    BLAST.configureAutomaticYield();
    BLAST.configureClaimableGas();
    BLAST.configureGovernor(governor_);
  }

  function blastPointsAdmin() external view returns (address) {
    return governor;
  }
}
