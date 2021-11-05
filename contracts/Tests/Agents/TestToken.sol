// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.7.0;

import "./TestTokenWithDecimals.sol";

contract TestToken is TestTokenWithDecimals {
  constructor(
    address admin,
    string memory name,
    string memory symbol
  ) TestTokenWithDecimals(admin, name, symbol, 18) {}
}
