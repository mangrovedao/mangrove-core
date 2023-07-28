// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/MgvLib.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {ISignatureTransfer} from "lib/permit2/src/interfaces/ISignatureTransfer.sol";
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

  ///@notice router-dependent implementation of the `pull` function
  ///@param token Token to be transferred
  ///@param owner determines the location of the reserve (router implementation dependent).
  ///@param amount The amount of tokens to be transferred
  ///@param strict wether the caller maker contract wishes to pull at most `amount` tokens of owner.
  ///@param permit provided by user
  ///@return pulled The amount pulled if successful; otherwise, 0.
  function __pull__(
    IERC20 token,
    address owner,
    uint amount,
    bool strict,
    ISignatureTransfer.PermitTransferFrom calldata permit,
    bytes calldata signature
  ) internal virtual override returns (uint pulled) {
    amount = strict ? amount : token.balanceOf(owner);
    if (TransferLib.transferTokenFromWithPermit2Signature(permit2, owner, msg.sender, amount, permit, signature)) {
      return amount;
    } else {
      return 0;
    }
  }

  ///@notice router-dependent implementation of the `checkList` function
  ///@notice verifies all required approval involving `this` router (either as a spender or owner)
  ///@dev `checkList` returns normally if all needed approval are strictly positive. It reverts otherwise with a reason.
  ///@param token is the asset whose approval must be checked
  ///@param owner the account that requires asset pulling/pushing
  function __checkList__(IERC20 token, address owner) internal view virtual override {
    // verifying that `this` router can withdraw tokens from owner (required for `withdrawToken` and `pull`)
    require(token.allowance(owner, address(permit2)) > 0, "SimpleRouter/NotApprovedByOwner");
  }
}
