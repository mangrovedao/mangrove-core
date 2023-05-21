// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

import {IERC20} from "mgv_src/MgvLib.sol";
import "./IStrategyComplete.sol";

interface IVault is IERC20 {
  function deposit(uint) external;
  function depositAll() external;
  function withdraw(uint) external;
  function withdrawAll() external;
  function getPricePerFullShare() external view returns (uint);
  function upgradeStrat() external;
  function balance() external view returns (uint);
  function want() external view returns (IERC20);
  function strategy() external view returns (IStrategyComplete);
}
