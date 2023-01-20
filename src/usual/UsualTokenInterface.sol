// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.14;

import {IERC20} from "mgv_src/IERC20.sol";
import {ERC20} from "mgv_src/toy/ERC20.sol";

abstract contract UsualTokenInterface is ERC20 {
  // should burn the "amount" of this token and transfer the underlying to the "account"
  function unlockFor(address account, uint amount) public virtual returns (bool) {}
}
