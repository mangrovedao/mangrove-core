// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./MintableERC20BLWithDecimals.sol";
import "forge-std/console.sol";

contract LimitedMintableERC20WithDecimals is MintableERC20BLWithDecimals {
  mapping(address => uint) public lastMints;

  constructor(address admin, string memory name, string memory symbol, uint8 _decimals)
    MintableERC20BLWithDecimals(admin, name, symbol, _decimals)
  {}

  function mint(address to, uint amount) external override {
    uint lastMint = lastMints[to];

    require(
      admins[msg.sender] == true || lastMint == 0 || (lastMint + 1 days) < block.timestamp,
      "LimitedMintableERC20WithDecimals/lastMintToRecent"
    );
    mintRestricted(to, amount);
    lastMints[to] = amount;
  }
}
