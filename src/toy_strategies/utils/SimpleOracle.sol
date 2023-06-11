// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import "../interfaces/IOracle.sol";
import "mgv_src/strategies/utils/AccessControlled.sol";
import {IERC20} from "../../MgvLib.sol";

contract SimpleOracle is IOracle, AccessControlled {
  address reader; // if unset, anyone can read price
  IERC20 public immutable base_token;
  mapping(address => uint96) internal priceData;

  constructor(address base_, address admin) AccessControlled(admin) {
    base_token = IERC20(base_);
    try base_token.decimals() returns (uint8 d) {
      require(d != 0, "Invalid decimals number for Oracle base");
    } catch {
      revert("Invalid Oracle base address");
    }
  }

  function decimals() external view override returns (uint8) {
    return base_token.decimals();
  }

  function setReader(address reader_) external onlyAdmin {
    reader = reader_;
  }

  function setPrice(address token, uint price) external override onlyAdmin {
    require(uint96(price) == price, "price overflow");
    priceData[token] = uint96(price);
  }

  function getPrice(address token) external view override onlyCaller(reader) returns (uint96 price) {
    price = priceData[token];
    require(price != 0, "missing price data");
  }
}
