// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./ERC20BL2.sol";

contract ERC20BLWithDecimals is ERC20BL {
  constructor(string memory __name, string memory __symbol, uint8 __decimals) ERC20BL(__name, __symbol) {
    _decimals = __decimals;
  }
}
