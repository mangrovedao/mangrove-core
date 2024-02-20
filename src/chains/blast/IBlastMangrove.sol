// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IMangrove} from "../../IMangrove.sol";
import {IBlastPoints} from "./interfaces/IBlastPoints.sol";

/// @title IBlastMangrove
/// @notice Interface to implement blast mangrove
interface IBlastMangrove is IMangrove, IBlastPoints {}
