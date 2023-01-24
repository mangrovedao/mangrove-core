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
//import {console2 as console} from "forge-std/Test.sol";

///@title Router acting as a liquidity reserve on AAVE for multiple maker contracts.

contract AavePooledRouter is AaveV3Module, AbstractRouter {
  event SetRewardsManager(address);

  mapping(IERC20 => uint) internal _totalShares;
  mapping(IERC20 => mapping(address => uint)) internal _sharesOf;
  IERC20 public _buffer;
  address public _rewardsManager;

  ///@notice initial shares to be minted
  ///@dev this amount must be big enough to avoid minting 0 shares via "donation"
  ///see https://github.com/code-423n4/2022-09-y2k-finance-findings/issues/449
  uint public constant INIT_SHARES = 10 ** 29;

  modifier isThis(address reserve) {
    require(reserve == address(this), "AavePooledReserve/mustBeThis");
    _;
  }

  constructor(address _addressesProvider, uint _referralCode, uint _interestRateMode, uint overhead)
    AaveV3Module(_addressesProvider, _referralCode, _interestRateMode)
    AbstractRouter(overhead) // not permissioned
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
    flushAndsetBuffer(token);
    _mintShares(token, maker, amount);

    // Transfer must occur *after* _mintShares above
    require(TransferLib.transferTokenFrom(token, maker, reserve, amount), "AavePooledRouter/pushFailed");

    return amount;
  }

  ///@notice declares that an incoming asset should be buffered locally and not flushed to AAVE
  ///@notice flushes previously buffered tokens to AAVE
  ///@param token the address of the asset
  function flushAndsetBuffer(IERC20 token) public makersOrAdmin {
    IERC20 tokenInBuffer = _buffer;
    if (tokenInBuffer != token && tokenInBuffer != IERC20(address(0))) {
      _repayThenDeposit(tokenInBuffer, address(this), tokenInBuffer.balanceOf(address(this)));
    }
    _buffer = token;
  }

  ///@inheritdoc AbstractRouter
  function __pull__(IERC20 token, address reserve, address maker, uint amount, bool strict)
    internal
    override
    isThis(reserve)
    returns (uint)
  {
    // if there is any buffered liquidity (!= token), we push it back to AAVE
    flushAndsetBuffer(token);

    uint amount_ = strict ? amount : reserveBalance(token, maker, reserve);
    _burnShares(token, maker, amount_);

    // pulling all funds from AAVE to be ready to serve for the rest of the market order
    (uint totalRedeemable,) = maxGettableUnderlying(token, false, address(this));
    _redeem(token, totalRedeemable, address(this));

    // Transfering funds to the maker contract
    amount_ = amount_ < totalRedeemable ? amount_ : totalRedeemable;
    require(TransferLib.transferToken(token, maker, amount_), "AavePooledRouter/pullFailed");
    return amount_;
  }

  ///@inheritdoc AbstractRouter
  function __checkList__(IERC20 token, address reserve) internal view override {
    // allowance for `withdrawToken` and `pull`
    require( // required prior to withdraw from POOL
    reserve == address(this), "AavePooledRouter/ReserveMustBeRouter");
    // allowance for `push`
    require( // required to supply or repay
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
