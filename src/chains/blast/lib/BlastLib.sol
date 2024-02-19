// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IBlast} from "../interfaces/IBlast.sol";

/// @title BlastLib
/// @author Mangrove
/// @notice A library that contains the BLAST contract address
library BlastLib {
  IBlast public constant BLAST = IBlast(0x4300000000000000000000000000000000000002);
}
