// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.7.0;
pragma abicoder v2;

import "../../MgvLib.sol";

library L {
  event TradeSuccess(MgvLib.SingleOrder order, address taker);
  event TradeFail(MgvLib.SingleOrder order, address taker);
}

contract MgvMonitor is IMgvMonitor {
  uint gasprice;
  mapping(address => mapping(address => uint)) private densities;

  function setGasprice(uint _gasprice) external {
    gasprice = _gasprice;
  }

  function setDensity(
    address base,
    address quote,
    uint _density
  ) external {
    densities[base][quote] = _density;
  }

  function read(address base, address quote)
    external
    view
    override
    returns (uint, uint)
  {
    return (gasprice, densities[base][quote]);
  }

  function notifySuccess(MgvLib.SingleOrder calldata sor, address taker)
    external
    override
  {
    emit L.TradeSuccess(sor, taker);
  }

  function notifyFail(MgvLib.SingleOrder calldata sor, address taker)
    external
    override
  {
    emit L.TradeFail(sor, taker);
  }
}
