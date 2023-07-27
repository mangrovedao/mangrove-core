// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/MgvLib.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {SimpleRouter} from "./SimpleRouter.sol";

contract Permit2Router is SimpleRouter {
  IPermit2 permit2;

  constructor(IPermit2 _permit2) SimpleRouter() {
    permit2 = _permit2;
  }

  function __pull__(IERC20 token, address owner, uint amount, bool strict)
    internal
    virtual
    override
    returns (uint pulled)
  {
    amount = strict ? amount : token.balanceOf(owner);
    if (TransferLib.transferTokenFromWithPermit2(permit2, token, owner, msg.sender, amount)) {
      return amount;
    } else {
      return 0;
    }
  }
}
