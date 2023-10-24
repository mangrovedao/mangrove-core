// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import "@mgv/src/core/MgvLib.sol";

///@title This library helps with safely interacting with ERC20 tokens
///@notice Transferring 0 or to self will be skipped.
///@notice ERC20 tokens returning bool instead of reverting are handled.
library TransferLib {
  ///@notice This transfer amount of token to recipient address
  ///@param token Token to be transferred
  ///@param recipient Address of the recipient the tokens will be transferred to
  ///@param amount The amount of tokens to be transferred
  ///@return true if transfer was successful; otherwise, false.
  function transferToken(IERC20 token, address recipient, uint amount) internal returns (bool) {
    if (amount == 0) {
      return true;
    }
    if (recipient == address(this)) {
      return token.balanceOf(recipient) >= amount;
    }
    return _transferToken(token, recipient, amount);
  }

  ///@notice This transfer amount of token to recipient address
  ///@param token Token to be transferred
  ///@param recipient Address of the recipient the tokens will be transferred to
  ///@param amount The amount of tokens to be transferred
  ///@return true if transfer was successful; otherwise, false.
  function _transferToken(IERC20 token, address recipient, uint amount) private returns (bool) {
    // This low level call will not revert but instead return success=false if callee reverts, so we
    // verify that it does not revert by checking success, but we also have to check
    // the returned data if any since some ERC20 tokens to not strictly follow the standard of reverting
    // but instead return false.
    (bool success, bytes memory data) =
      address(token).call(abi.encodeWithSelector(token.transfer.selector, recipient, amount));
    return (success && (data.length == 0 || abi.decode(data, (bool))));
  }

  ///@notice This transfer amount of token to recipient address from spender address
  ///@param token Token to be transferred
  ///@param spender Address of the spender, where the tokens will be transferred from
  ///@param recipient Address of the recipient, where the tokens will be transferred to
  ///@param amount The amount of tokens to be transferred
  ///@return true if transfer was successful; otherwise, false.
  function transferTokenFrom(IERC20 token, address spender, address recipient, uint amount) internal returns (bool) {
    if (amount == 0) {
      return true;
    }
    if (spender == recipient) {
      return token.balanceOf(spender) >= amount;
    }
    // optimization to avoid requiring contract to approve itself
    if (spender == address(this)) {
      return _transferToken(token, recipient, amount);
    }
    return _transferTokenFrom(token, spender, recipient, amount);
  }

  ///@notice This transfer amount of token to recipient address from spender address
  ///@param token Token to be transferred
  ///@param spender Address of the spender, where the tokens will be transferred from
  ///@param recipient Address of the recipient, where the tokens will be transferred to
  ///@param amount The amount of tokens to be transferred
  ///@return true if transfer was successful; otherwise, false.
  function _transferTokenFrom(IERC20 token, address spender, address recipient, uint amount) private returns (bool) {
    // This low level call will not revert but instead return success=false if callee reverts, so we
    // verify that it does not revert by checking success, but we also have to check
    // the returned data if there since some ERC20 tokens to not strictly follow the standard of reverting
    // but instead return false.
    (bool success, bytes memory data) =
      address(token).call(abi.encodeWithSelector(token.transferFrom.selector, spender, recipient, amount));
    return (success && (data.length == 0 || abi.decode(data, (bool))));
  }

  ///@notice ERC20 approval, handling non standard approvals that do not return a value
  ///@param token the ERC20
  ///@param spender the address whose allowance is to be given
  ///@param amount of the allowance
  ///@return true if approval was successful; otherwise, false.
  function _approveToken(IERC20 token, address spender, uint amount) private returns (bool) {
    // This low level call will not revert but instead return success=false if callee reverts, so we
    // verify that it does not revert by checking success, but we also have to check
    // the returned data if any since some ERC20 tokens to not strictly follow the standard of reverting
    // but instead return false.
    (bool success, bytes memory data) =
      address(token).call(abi.encodeWithSelector(token.approve.selector, spender, amount));
    return (success && (data.length == 0 || abi.decode(data, (bool))));
  }

  ///@notice ERC20 approval, handling non standard approvals that do not return a value
  ///@param token the ERC20
  ///@param spender the address whose allowance is to be given
  ///@param amount of the allowance
  ///@return true if approval was successful; otherwise, false.
  function approveToken(IERC20 token, address spender, uint amount) internal returns (bool) {
    return _approveToken(token, spender, amount);
  }
}
