// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/MgvLib.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {ISignatureTransfer} from "lib/permit2/src/interfaces/ISignatureTransfer.sol";
import {SimpleRouterWithoutGasReq} from "./SimpleRouter.sol";

contract Permit2Router is SimpleRouterWithoutGasReq {
  IPermit2 public permit2;

  constructor(IPermit2 _permit2) SimpleRouterWithoutGasReq(74_000) {
    permit2 = _permit2;
  }

  /// @notice transfers an amount of tokens from the reserve to the maker.
  /// @param token Token to be transferred
  /// @param owner The account from which the tokens will be transferred.
  /// @param amount The amount of tokens to be transferred
  /// @param strict wether the caller maker contract wishes to pull at most `amount` tokens of owner.
  /// @return pulled The amount pulled if successful (will be equal to `amount`); otherwise, 0.
  /// @dev requires approval from `owner` for `this` to transfer `token`.
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
  ///@param transferDetails The spender's requested transfer details for the permitted token
  ///@param signature The signature to verify
  ///@return pulled The amount pulled if successful; otherwise, 0.
  function __pull__(
    IERC20 token,
    address owner,
    uint amount,
    bool strict,
    ISignatureTransfer.PermitTransferFrom calldata transferDetails,
    bytes calldata signature
  ) internal returns (uint pulled) {
    amount = strict ? amount : token.balanceOf(owner);
    if (
      TransferLib.transferTokenFromWithPermit2Signature(permit2, owner, msg.sender, amount, transferDetails, signature)
    ) {
      return amount;
    } else {
      return 0;
    }
  }

  ///@notice pulls liquidity from the reserve and sends it to the calling maker contract.
  ///@param token is the ERC20 managing the pulled asset
  ///@param reserveId identifies the fund owner (router implementation dependent).
  ///@param amount of `token` the maker contract wishes to pull from its reserve
  ///@param strict when the calling maker contract accepts to receive more funds from reserve than required (this may happen for gas optimization)
  ///@param permit The permit data signed over by the owner
  ///@param signature The signature to verify
  ///@return pulled the amount that was successfully pulled.
  function pull(
    IERC20 token,
    address reserveId,
    uint amount,
    bool strict,
    ISignatureTransfer.PermitTransferFrom calldata permit,
    bytes calldata signature
  ) external onlyBound returns (uint pulled) {
    if (strict && amount == 0) {
      return 0;
    }
    pulled = __pull__(token, reserveId, amount, strict, permit, signature);
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
