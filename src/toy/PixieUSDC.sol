// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {MintableERC20BLWithDecimals} from "./MintableERC20BLWithDecimals.sol";

contract PixieUSDC is MintableERC20BLWithDecimals {
  constructor(address admin) MintableERC20BLWithDecimals(admin, "Pixie USDC", "PxUSDC", 6) {}
}
