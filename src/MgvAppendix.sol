// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {MgvLib, IMgvMonitor, MgvStructs, IERC20, Leaf, Field, Density, DensityLib, OLKey} from "./MgvLib.sol";
import {MgvView} from "mgv_src/MgvView.sol";
import {MgvGovernable} from "mgv_src/MgvGovernable.sol";

// Contains view and gov functions, to reduce Mangrove contract size
contract MgvAppendix is MgvView, MgvGovernable {}
