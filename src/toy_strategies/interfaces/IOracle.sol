// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

interface IOracle {
  function decimals() external view returns (uint8);

  function getPrice(address token) external view returns (uint96);

  function setPrice(address token, uint price) external;
}
