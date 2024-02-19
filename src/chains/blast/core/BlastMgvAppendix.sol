// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {MgvGovernable} from "../../../core/MgvGovernable.sol";
import {BlastMgvView} from "./BlastMgvView.sol";

/// @title BlastMgvAppendix
/// @notice A contract that inherits MgvGovernable and BlastMgvView
contract BlastMgvAppendix is MgvGovernable, BlastMgvView {}
