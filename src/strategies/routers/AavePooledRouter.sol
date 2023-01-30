// SPDX-License-Identifier:	BSD-2-Clause

//AavePoolManager.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;

import {AbstractRouter} from "./AbstractRouter.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {HasAaveBalanceViewMonad, IERC20} from "./HasAaveBalanceViewMonad.sol";

///@title Router acting as a liquidity reserve on AAVE for multiple depositors (possibly coming from different maker contracts).
///@notice maker contracts deposit/withdraw their user(s) fund(s) on this router, which maintains an accounting of shares attributed to each depositors
///@dev deposit is made via `pushAndSupply`, and withdraw is made via `pull` with `strict=true`.
///@dev this router ensures an optimal gas cost complexity when the following strategy is used:
/// * on the offer logic side:
///    * in `makerExecute`, check whether logic is the first caller to the router. This is done by checking whether the balance of outbound tokens of the router is below the required amount. If so the logic should return a special bytes32 (say `"firstCaller"`) to makerPosthook.
///    * in `__put__`  the logic stores incoming liquidity on the strat balance
///    * in `__get__` the logic pulls liquidity from the router in a non strict manner
///    * in __posthookSuccess|Fallback__ the logic pushes both inbound and outbound tokens to the router. If message from makerExecute is `"firstCaller"`, the logic additionally asks the router to supply all its outbound and inbound tokens to AAVE. This can be done is a single step by calling `pushAndSupply`
/// * on the router side:
///    * `__pull__`  checks whether local balance of token is below required amount. If so it pulls all its funds from AAVE (this includes funds that do not belong to the owner of the calling contract) and sends to caller all the owner's reserve (according to the shares attributed to the owner). This router then decreases owner's shares accordingly. (note that if AAVE has no liquidity crisis, then the owner's shares will be temporarily 0)
///    * `__push__` transfers the requested amount of tokens from the calling maker contract and increases owner's shares, but does not supply on AAVE

contract AavePooledRouter is HasAaveBalanceViewMonad, AbstractRouter {
  // keep _rewardsManager on slot(0) to avoid breaking tests
  address _rewardsManager;

  event SetRewardsManager(address);

  mapping(IERC20 => uint) internal _totalShares;
  mapping(IERC20 => mapping(address => uint)) internal _sharesOf;

  ///@notice initial shares to be minted
  ///@dev this amount must be big enough to avoid minting 0 shares via "donation"
  ///see https://github.com/code-423n4/2022-09-y2k-finance-findings/issues/449
  /// mitagation proposed here: https://ethereum-magicians.org/t/address-eip-4626-inflation-attacks-with-virtual-shares-and-assets/12677
  uint constant INIT_SHARES = 10 ** 29;

  constructor(address _addressesProvider, uint overhead)
    HasAaveBalanceViewMonad(_addressesProvider)
    AbstractRouter(overhead)
  {
    setRewardsManager(msg.sender);
  }

  ///@notice returns the shares of this router's balance that a maker contract has
  ///@param token the address of the asset
  ///@param owner the address of the owner whose shares are requested
  ///@return shares the amount of shares of the owner.
  ///@dev `sharesOf(token,owner)/totalShares(token)` represent the portion of this contract's balance of `token`s that the owner can claim
  function sharesOf(IERC20 token, address owner) public view returns (uint shares) {
    shares = _sharesOf[token][owner];
  }

  ///@notice returns the total shares one needs to possess to claim all the tokens of this contract
  ///@param token the address of the asset
  ///@return total the total amount of shares
  ///@dev `sharesOf(token,maker)/totalShares(token)` represent the portion of this contract's balance of `token`s that the maker can claim
  function totalShares(IERC20 token) public view returns (uint total) {
    total = _totalShares[token];
  }

  ///@notice theoretically available funds to this router either in overlying or in tokens (part of it may be not redeemable from AAVE)
  ///@param token the asset whose balance one is querying
  ///@return balance of the asset
  ///@dev this function relies on the aave promise that aToken are in one-to-one correspondance with claimable underlying and use the same decimals
  ///FIXME use viewMonad for the balances
  function totalBalance(IERC20 token) external view returns (uint balance) {
    BalanceViewMonad memory v_tkn;
    balance = _balanceOf(token, address(this), v_tkn) + _balanceOfOverlying(token, address(this), v_tkn);
  }

  function totalBalance(IERC20 token, BalanceViewMonad memory v_tkn) internal view returns (uint balance) {
    balance = _balanceOf(token, address(this), v_tkn) + _balanceOfOverlying(token, address(this), v_tkn);
  }

  ///@notice computes available funds (modulo available liquidity on aave) for a given owner
  ///@param token the asset one wants to know the balance of
  ///@param owner the owner whose balance is queried
  function ownerBalance(IERC20 token, address owner) public view override returns (uint) {
    uint totalShares_ = totalShares(token);
    BalanceViewMonad memory v_tkn;
    return totalShares_ == 0 ? 0 : sharesOf(token, owner) * totalBalance(token, v_tkn) / totalShares_;
  }

  //
  function ownerBalance(IERC20 token, address owner, BalanceViewMonad memory v_tkn) internal view returns (uint) {
    uint totalShares_ = totalShares(token);
    return totalShares_ == 0 ? 0 : sharesOf(token, owner) * totalBalance(token, v_tkn) / totalShares_;
  }

  ///@notice computes how many shares an amount of tokens represents
  ///@param token the address of the asset
  ///@param amount of tokens
  ///@return shares the shares that correspond to amount
  function _sharesOfamount(IERC20 token, uint amount, BalanceViewMonad memory v_tkn)
    internal
    view
    returns (uint shares)
  {
    uint totalShares_ = totalShares(token);
    shares = totalShares_ == 0 ? INIT_SHARES : totalShares_ * amount / totalBalance(token, v_tkn);
  }

  ///@notice mints a certain quantity of shares for a given asset and assigns them to a maker contract
  ///@param token the address of the asset
  ///@param owner the address of owner for whom new shares will be assigned
  ///@param amount the amount of assets added to maker's reserve
  function _mintShares(IERC20 token, address owner, uint amount, BalanceViewMonad memory v_tkn) internal {
    // computing how many shares should be minted for maker contract
    uint sharesToMint = _sharesOfamount(token, amount, v_tkn);
    _sharesOf[token][owner] += sharesToMint;
    _totalShares[token] += sharesToMint;
  }

  ///@notice burns a certain quantity of maker shares for a given asset
  ///@param token the address of the asset
  ///@param owner the address of the owner whose shares are being burnt
  ///@param amount the amount of assets withdrawn from maker's reserve
  function _burnShares(IERC20 token, address owner, uint amount, BalanceViewMonad memory v_tkn) internal {
    // computing how many shares should be minted for maker contract
    uint sharesToBurn = _sharesOfamount(token, amount, v_tkn);
    uint ownerShares = _sharesOf[token][owner];
    require(sharesToBurn <= ownerShares, "AavePooledRouter/insufficientFunds");
    _sharesOf[token][owner] = ownerShares - sharesToBurn;
    _totalShares[token] -= sharesToBurn;
  }

  ///@inheritdoc AbstractRouter
  function __push__(IERC20 token, address owner, uint amount) internal override returns (uint) {
    BalanceViewMonad memory v_tkn;
    _mintShares(token, owner, amount, v_tkn);
    // Transfer must occur *after* _mintShares above
    require(TransferLib.transferTokenFrom(token, msg.sender, address(this), amount), "AavePooledRouter/pushFailed");
    return amount;
  }

  ///@notice deposit local balance of an asset on the pool
  ///@param token the address of the asset
  function flushBuffer(IERC20 token) public makersOrAdmin {
    _supply(token, token.balanceOf(address(this)), address(this));
  }

  ///@notice push each token given in argument and supply the whole local balance on AAVE
  ///@param tokens the list of tokens that are being pushed to reserve
  ///@param amounts the quantities of tokens one wishes to push
  ///@return pushed the pushed quantities for each token
  ///@dev an offer logic should call this instead of `flush` when it is the last posthook to be executed
  ///@dev this function is also to be used when user deposits funds on the maker contract
  ///@dev this can be determined by checking during __lastLook__ whether the logic will trigger a withdraw from aave (this is the case is router's balance of token is empty)
  function pushAndSupply(IERC20[] calldata tokens, uint[] calldata amounts, address owner)
    external
    onlyMakers
    returns (uint[] memory pushed)
  {
    pushed = new uint[](tokens.length);
    for (uint i; i < tokens.length; i++) {
      pushed[i] = __push__(tokens[i], owner, amounts[i]);
      flushBuffer(tokens[i]);
    }
  }

  ///@inheritdoc AbstractRouter
  ///@dev outside a market order (i.e if pulled is not called during offer logic's execution) the `token` balance of this router should be empty.
  /// This may not be the case when a "donation" occurred to this contract
  /// If the donation is large enough to cover the pull request we use the donation funds
  function __pull__(IERC20 token, address owner, uint amount, bool strict) internal override returns (uint) {
    uint toRedeem;
    uint amount_ = amount;
    BalanceViewMonad memory v_tkn;
    uint buffer = _balanceOf(token, address(this), v_tkn);
    if (strict) {
      // maker contract is making a deposit (not a call emanating from the offer logic)
      toRedeem = buffer > amount ? 0 : amount - buffer;
    } else {
      // we redeem all router's available balance from aave and transfer to maker all its balance
      amount_ = ownerBalance(token, owner, v_tkn); // max possible transfer to maker
      if (buffer < amount) {
        // this pull is the first of the market order (that requires funds from aave) so we redeem all the reserve from AAVE
        // note in theory we should check buffer == 0 but donation may have occurred.
        // This check forces donation to be at least the amount of outbound tokens promised by caller to avoid grieffing (depositing a small donation to make offer fail).
        toRedeem = _balanceOfOverlying(token, address(this), v_tkn);
      } else {
        // since buffer > amount, this call is not the first pull of the market order (unless a big donation occurred) and we do not withdraw from AAVE
        amount_ = buffer > amount_ ? amount_ : buffer;
        // if buffer < amount_ we still have buffer > amount (maker initial quantity)
      }
    }
    // now that we know how much we send to maker contract, we try to burn the corresponding shares, this will underflow if owner does not have enough shares
    _burnShares(token, owner, amount_, v_tkn);

    // redeem does not change amount of shares. We do this after burning to avoid redeeming on AAVE if caller doesn't have the required funds.
    if (toRedeem > 0) {
      // this call will throw if AAVE has a liquidity crisis
      _redeem(token, toRedeem, address(this));
    }

    // Transfering funds to the maker contract, at this point we must revert if things go wrong because shares have been burnt on the premise that `amount_` will be transferred.
    require(TransferLib.transferToken(token, msg.sender, amount_), "AavePooledRouter/pullFailed");
    return amount_;
  }

  ///@inheritdoc AbstractRouter
  function __checkList__(IERC20 token, address owner) internal view override {
    // any owner passes the checklist since this router does not pull or push liquidity to it
    owner;
    // we check that `token` is listed on AAVE
    require(checkAsset(token), "AavePooledRouter/tokenNotLendableOnAave");
    require( // required to supply or withdraw token on pool
    token.allowance(address(this), address(POOL)) > 0, "AavePooledRouter/hasNotApprovedPool");
  }

  ///@inheritdoc AbstractRouter
  function __activate__(IERC20 token) internal virtual override {
    _approveLender(token, type(uint).max);
  }

  ///@notice revokes pool approval for a certain asset. This router will no longer be able to deposit on Pool
  ///@param token the address of the asset whose approval must be revoked.
  function revokeLenderApproval(IERC20 token) external onlyAdmin {
    _approveLender(token, 0);
  }

  ///@notice allows rewards manager to claim the rewards attributed to this router by AAVE
  ///@param assets the list of overlyings (aToken, debtToken) whose rewards should be claimed
  ///@dev if some rewards are elligible they are sent to `_rewardsManager`
  ///@return rewardsList the addresses of the claimed rewards
  ///@return claimedAmounts the amount of claimed rewards
  function claimRewards(address[] calldata assets)
    external
    onlyCaller(_rewardsManager)
    returns (address[] memory rewardsList, uint[] memory claimedAmounts)
  {
    return _claimRewards(assets, msg.sender);
  }

  ///@notice sets a new rewards manager
  ///@dev if any rewards is active for pure lenders, `_rewardsManager` will be able to claim them
  function setRewardsManager(address rewardsManager) public onlyAdmin {
    require(rewardsManager != address(0), "AavePooledReserve/0xrewardsManager");
    _rewardsManager = rewardsManager;
    emit SetRewardsManager(rewardsManager);
  }
}
