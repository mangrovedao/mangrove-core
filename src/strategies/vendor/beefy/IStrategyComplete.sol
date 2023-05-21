// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "mgv_src/MgvLib.sol";

interface IStrategyComplete {
  function vault() external view returns (address);
  function want() external view returns (IERC20);
  function beforeDeposit() external;
  function deposit() external;
  function withdraw(uint) external;
  function balanceOf() external view returns (uint);
  function balanceOfWant() external view returns (uint);
  function balanceOfPool() external view returns (uint);
  function harvest() external;
  function retireStrat() external;
  function panic() external;
  function pause() external;
  function unpause() external;
  function paused() external view returns (bool);
  function owner() external view returns (address);
  function keeper() external view returns (address);
  function setKeeper(address) external;
  function unirouter() external view returns (address);
  function beefyFeeRecipient() external view returns (address);
  function setBeefyFeeRecipient(address) external;
  function strategist() external view returns (address);
  function setStrategist(address) external;
}
