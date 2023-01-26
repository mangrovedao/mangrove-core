// SPDX-License-Identifier:	BSD-2-Clause

//AavePoolManager.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;

import {AbstractRouter, IERC20} from "./AbstractRouter.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {AaveV3Module, IRewardsControllerIsh} from "mgv_src/strategies/integrations/AaveV3Module.sol";
import {console} from "forge-std/Test.sol";

///@title Router acting as a liquidity reserve on AAVE for multiple maker contracts.
///@notice this router has an optimal gas cost complexity when all maker contracts binding to it comply with the following offer logic:
/// * on the offer logic side (Kandel's):
///    * in `makerExecute`, check whether we are the first caller to the router. You can know this by checking whether the balance of outbound tokens of the router is 0. If so send a special IamLast:bytes32 to makerPosthook  (this is done in __lastLook__ )
///    * in `__put__`  simply stores incoming liquidity on the strat (don't do anything de facto)
///    * in `__get__` pull liquidity from the router in a non strict manner (i.e allow the router to send you more than what you need, in the limits of your shares of the reserve)
///    * in __posthookSuccess|Fallback__ push both inbound and outbound tokens to the router. If message from makerExecute is IamLast , tell the router to flush all its buffer of outbound and inbound tokens to AAVE.
/// * on the router side:
///    * `__pull__`  checks whether local balance of token is 0. If so it pulls everything from AAVE and sends to caller all it's reserve (the part of the reserve that he is allowed to redeem). Decrease caller's shares accordingly (notice you cannot put the shares to 0 w/o verification since not all funds might be redeemable from aave)
///    * `__push__` transfer the requested amount of tokens from the calling maker contract but does not supply on AAVE
///       a special function `pushAndSupply` transfers the tokens from the caller and supplies the total balance of the router on AAVE
///       both `__push__` and `pushAndSupply` assign new shares to the caller.

contract AavePooledRouter is AaveV3Module, AbstractRouter {
  // keep _rewardsManager on slot(0) to avoid breaking tests
  address _rewardsManager;

  event SetRewardsManager(address);

  mapping(IERC20 => uint) internal _totalShares;
  mapping(IERC20 => mapping(address => uint)) internal _sharesOf;

  ///@notice initial shares to be minted
  ///@dev this amount must be big enough to avoid minting 0 shares via "donation"
  ///see https://github.com/code-423n4/2022-09-y2k-finance-findings/issues/449
  uint constant INIT_SHARES = 10 ** 29;

  modifier isThis(address reserve) {
    require(reserve == address(this), "AavePooledReserve/mustBeThis");
    _;
  }

  constructor(address _addressesProvider, uint _referralCode, uint _interestRateMode, uint overhead)
    AaveV3Module(_addressesProvider, _referralCode, _interestRateMode)
    AbstractRouter(overhead)
  {
    setRewardsManager(msg.sender);
  }

  ///@notice returns the shares of this router's balance that a maker contract has
  ///@param token the address of the asset
  ///@param maker the address of the maker contract whose shares are requested
  ///@return shares the amount of shares of the maker contract.
  ///@dev `sharesOf(token,maker)/totalShares(token)` represent the portion of this contract's balance of `token`s that the maker can claim
  function sharesOf(IERC20 token, address maker) public view returns (uint) {
    return _sharesOf[token][maker];
  }

  ///@notice returns the total shares one needs to possess to claim all the tokens of this contract
  ///@param token the address of the asset
  ///@return total the total amount of shares
  ///@dev `sharesOf(token,maker)/totalShares(token)` represent the portion of this contract's balance of `token`s that the maker can claim
  function totalShares(IERC20 token) public view returns (uint total) {
    return _totalShares[token];
  }

  ///@notice theoretically available funds to this router either in overlying or in tokens (part of it may be not redeemable from AAVE)
  ///@param token the asset whose balance one is querying
  ///@return balance of the asset
  function totalBalance(IERC20 token) public view returns (uint balance) {
    balance = overlying(token).balanceOf(address(this)) + token.balanceOf(address(this));
  }

  ///@inheritdoc AbstractRouter
  function reserveBalance(IERC20 token, address maker, address reserve)
    public
    view
    override
    isThis(reserve)
    returns (uint)
  {
    uint totalShares_ = totalShares(token);
    return totalShares_ == 0 ? 0 : sharesOf(token, maker) * totalBalance(token) / totalShares_;
  }

  ///@notice computes how many shares should be minted if when some token balance of this router increases
  ///@param token the address of the asset whose balance will increase
  ///@param amount of the increase
  ///@return newShares the shares that must be minted
  function sharesOfamount(IERC20 token, uint amount) internal view returns (uint newShares) {
    uint totalShares_ = totalShares(token);
    newShares = totalShares_ == 0 ? INIT_SHARES : totalShares_ * amount / totalBalance(token);
  }

  ///@notice mints a certain quantity of shares for a given asset and assigns them to a maker contract
  ///@param token the address of the asset
  ///@param maker the address of the maker contract who should have the assets assigned
  ///@param amount the amount of assets added to maker's reserve
  function _mintShares(IERC20 token, address maker, uint amount) internal {
    // computing how many shares should be minted for maker contract
    uint sharesToMint = sharesOfamount(token, amount);
    _sharesOf[token][maker] += sharesToMint;
    _totalShares[token] += sharesToMint;
  }

  ///@notice burns a certain quantity of maker shares for a given asset
  ///@param token the address of the asset
  ///@param maker the address of the maker contract whose shares are being burnt
  ///@param amount the amount of assets withdrawn from maker's reserve
  function _burnShares(IERC20 token, address maker, uint amount) internal {
    // computing how many shares should be minted for maker contract
    uint sharesToBurn = sharesOfamount(token, amount);
    _sharesOf[token][maker] -= sharesToBurn;
    _totalShares[token] -= sharesToBurn;
  }

  ///@inheritdoc AbstractRouter
  function __push__(IERC20 token, address reserve, address maker, uint amount)
    internal
    override
    isThis(reserve)
    returns (uint)
  {
    _mintShares(token, maker, amount);
    // Transfer must occur *after* _mintShares above
    require(TransferLib.transferTokenFrom(token, maker, reserve, amount), "AavePooledRouter/pushFailed");
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
  function pushAndSupply(IERC20[] calldata tokens, uint[] calldata amounts)
    external
    onlyMakers
    returns (uint[] memory pushed)
  {
    pushed = new uint[](tokens.length);
    for (uint i; i < tokens.length; i++) {
      pushed[i] = __push__(tokens[i], address(this), msg.sender, amounts[i]);
      flushBuffer(tokens[i]);
    }
  }

  ///@inheritdoc AbstractRouter
  ///@dev if function returns less than `amount` this implies that either makerContract does not have enough reserve or AAVE is illiquid on the pulled asset
  function __pull__(IERC20 token, address reserve, address maker, uint amount, bool strict)
    internal
    override
    isThis(reserve)
    returns (uint)
  {
    uint toRedeem;
    uint amount_ = amount;
    uint buffer = token.balanceOf(reserve);
    if (strict) {
      // maker contract is making a deposit (not a call of the offer logic)
      toRedeem = buffer > amount ? 0 : amount - buffer;
    } else {
      // we redeem all router's available balance from aave and transfer to maker all its balance
      amount_ = reserveBalance(token, maker, reserve); // max possible transfer to maker
      if (buffer < amount) {
        // this pull is the first of the market order so we redeem all the reserve from AAVE
        // note in theory we should check buffer == 0 but donation may have occurred.
        // This check forces donation to be at least the amount of outbound tokens promised by caller.
        (toRedeem,) = maxGettableUnderlying(token, false, /*not borrowing*/ reserve);
        if (toRedeem < amount_) {
          // AAVE has a liquidity crisis in `token` asset since redeemable is less than maker's reserve.
          // we revert before withdrawing from AAVE to spare some of maker's bounty
          require(toRedeem + buffer < amount, "AavePooledRouter/IlliquidPool");
          amount_ = toRedeem;
        }
      } else {
        // since buffer > amount, this call is not the first pull of the market order (unless a big donation occurred) and we do not withdraw from AAVE
        amount_ = buffer > amount_ ? amount_ : buffer;
        // if buffer < amount_ we still have buffer > amount (maker initial quantity)
      }
    }
    if (toRedeem > 0) {
      _redeem(token, toRedeem, reserve);
    }
    // now that we know how much we send to maker contract, we try to burn the corresponding shares, this will underflow if maker does not have enough shares
    _burnShares(token, maker, amount_);

    // Transfering funds to the maker contract, at this point we must revert if things go wrong because shares have been burnt on the premise that `amount_` will be transferred.
    require(TransferLib.transferToken(token, maker, amount_), "AavePooledRouter/pullFailed");
    return amount_;
  }

  ///@inheritdoc AbstractRouter
  function __checkList__(IERC20 token, address reserve) internal view override {
    require(reserve == address(this), "AavePooledRouter/ReserveMustBeRouter");
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
