// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IBlast} from "../interfaces/IBlast.sol";

/// @title BaseBlast
/// @author Mangrove
/// @notice A contract that sets the BLAST address
contract BaseBlast {
  /// @notice The address of the BLAST contract
  IBlast public constant BLAST = IBlast(0x4300000000000000000000000000000000000002);
}
