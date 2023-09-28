// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import "mgv_src/MgvLib.sol";
import {MgvView} from "mgv_src/MgvView.sol";
import {MgvGovernable} from "mgv_src/MgvGovernable.sol";

/* The `MgvAppendix` contract contains Mangrove functions related to:
 - Getters (view functions)
 - Governance functions
 
Due to bytecode size limits, not all Mangrove code can reside at the address of Mangrove. So when constructed, Mangrove creates a `MgvAppendix` instance and sets up a fallback to that instance when receiving an unknown function selector.

The functions moved to `MgvAppendix` have been selected because they are less gas-sensitive than core Mangove functionality. */
contract MgvAppendix is MgvView, MgvGovernable {}
