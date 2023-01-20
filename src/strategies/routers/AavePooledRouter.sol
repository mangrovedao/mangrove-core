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

contract AavePooledRouter is AaveV3Module, AbstractRouter {
  mapping(IERC20 => uint) internal _totalShares;
  mapping(IERC20 => mapping(address => uint)) internal _sharesOf;
  IERC20 _buffer;
  address _rewardsManager;

  // this should be enough so that INIT_SHARE * amount / reserveBalance does not underflow
  uint constant INIT_SHARES = 10 ** 29;

  modifier isThis(address reserve) {
    require(reserve == address(this), "AavePooledReserve/mustBeThis");
    _;
  }

  constructor(address _addressesProvider, uint _referralCode, uint _interestRateMode, uint overhead)
    AaveV3Module(_addressesProvider, _referralCode, _interestRateMode)
    AbstractRouter(overhead)
  {
    _rewardsManager = msg.sender;
  }

  function sharesOf(IERC20 token, address maker) public view returns (uint) {
    return _sharesOf[token][maker];
  }

  function totalShares(IERC20 token) public view returns (uint) {
    return _totalShares[token];
  }

  ///@notice theoretically available funds to this router either in overlying or in tokens (part of it may be not redeemable from AAVE)
  ///@param token the asset whose balance one is querying
  ///@return balance of the asset
  function totalBalance(IERC20 token) public view returns (uint balance) {
    balance = overlying(token).balanceOf(address(this)) + token.balanceOf(address(this));
  }

  ///@inheritdoc AbstractRouter
  function reserveBalance(IERC20 token, address reserve) public view override isThis(reserve) returns (uint) {
    return sharesOf(token, msg.sender) * totalBalance(token) / totalShares(token);
  }

  function sharesOfamount(IERC20 token, uint amount) internal view returns (uint shares) {
    uint totalShares_ = totalShares(token);
    shares = totalShares_ == 0 ? INIT_SHARES : totalShares_ * amount / totalBalance(token);
  }

  function _mintShares(IERC20 token, address maker, uint amount) internal {
    // computing how many shares should be minted for maker contract
    uint sharesToMint = sharesOfamount(token, amount);
    _sharesOf[token][maker] += sharesToMint;
    _totalShares[token] += sharesToMint;
  }

  function _burnShares(IERC20 token, address maker, uint amount) internal {
    // computing how many shares should be minted for maker contract
    uint sharesToBurn = sharesOfamount(token, amount);
    _sharesOf[token][maker] -= sharesToBurn;
    _totalShares[token] -= sharesToBurn;
  }

  function __push__(IERC20 token, address reserve, address maker, uint amount)
    internal
    override
    isThis(reserve)
    returns (uint)
  {
    _mintShares(token, maker, amount);
    require(TransferLib.transferTokenFrom(token, maker, reserve, amount), "AavePooledRouter/pushFailed");
    return amount;
  }

  function flushBuffer(IERC20 token) internal returns (IERC20 token_) {
    token_ = _buffer;
    if (token_ != token && token_ != IERC20(address(0))) {
      _repayThenDeposit(token_, address(this), token.balanceOf(address(this)));
    }
  }

  function __pull__(IERC20 token, address reserve, address maker, uint amount, bool strict)
    internal
    override
    isThis(reserve)
    returns (uint)
  {
    // if there is any buffered liquidity (!= token), we push it back to AAVE
    flushBuffer(token);

    uint amount_ = strict ? amount : reserveBalance(token, reserve);
    _burnShares(token, maker, amount_);

    // pulling all funds from AAVE to be ready to serve for the rest of the market order
    (uint totalRedeemable,) = maxGettableUnderlying(token, false, address(this));
    _redeem(token, totalRedeemable, address(this));

    // Transfering funds to the maker contract
    amount_ = amount_ < totalRedeemable ? amount_ : totalRedeemable;
    require(TransferLib.transferToken(token, maker, amount_), "AavePooledRouter/pullFailed");
    return amount_;
  }

  function __checkList__(IERC20 token, address reserve) internal view override {
    // allowance for `withdrawToken` and `pull`
    require( // required prior to withdraw from POOL
    reserve == address(this), "AavePooledRouter/ReserveMustBeRouter");
    // allowance for `push`
    require( // required to supply or repay
    token.allowance(address(this), address(POOL)) > 0, "AavePooledRouter/hasNotApprovedPool");
  }

  function __activate__(IERC20 token) internal virtual override {
    _approveLender(token, type(uint).max);
  }

  function revokeLenderApproval(IERC20 token) external onlyAdmin {
    _approveLender(token, 0);
  }

  function claimRewards(IRewardsControllerIsh rewardsController, address[] calldata assets)
    external
    onlyCaller(_rewardsManager)
    returns (address[] memory rewardsList, uint[] memory claimedAmounts)
  {
    return _claimRewards(rewardsController, assets);
  }

  function setRewardsManager(address rewardsManager) external onlyAdmin {
    require(rewardsManager != address(0), "AavePooledReserve/0xrewardsManager");
    _rewardsManager = rewardsManager;
  }
}
