// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {AbstractRouter} from "../AbstractRouter.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {AaveMemoizer, ReserveConfiguration} from "./AaveMemoizer.sol";
import {IERC20} from "mgv_src/IERC20.sol";

contract AavePrivateRouter is AaveMemoizer, AbstractRouter {
  ///@notice contract's constructor
  ///@param addressesProvider address of AAVE's address provider
  ///@param interestRate interest rate mode for borrowing assets. 0 for none, 1 for stable, 2 for variable
  ///@param overhead is the amount of gas that is required for this router to be able to perform a `pull` and a `push`.
  ///@dev `msg.sender` will be admin of this router
  constructor(address addressesProvider, uint interestRate, uint overhead)
    AaveMemoizer(addressesProvider, interestRate)
    AbstractRouter(overhead)
  {}

  ///@notice Deposit funds on this router from the calling maker contract
  ///@dev no transfer to AAVE is done at that moment.
  ///@inheritdoc AbstractRouter
  function __push__(IERC20 token, address, uint amount) internal override returns (uint) {
    require(TransferLib.transferTokenFrom(token, msg.sender, address(this), amount), "AavePrivateRouter/pushFailed");
    return amount;
  }

  ///@notice deposits router-local balance of an asset on the AAVE pool
  ///@param token the address of the asset
  function flushBuffer(IERC20 token) external onlyBound {
    Memoizer memory m;
    _repayThenDeposit(token, address(this), balanceOf(token, m));
  }

  ///@notice pushes each given token from the calling maker contract to this router, then supplies the whole router-local balance to AAVE
  ///@param token0 the first token to deposit
  ///@param amount0 the amount of `token0` to deposit
  ///@param token1 the second token to deposit
  ///@param amount1 the amount of `token1` to deposit
  ///@dev an offer logic should call this instead of `flush` when it is the last posthook to be executed
  ///@dev this can be determined by checking during __lastLook__ whether the logic will trigger a withdraw from AAVE (this is the case if router's balance of token is empty)
  ///@dev this call be performed even for tokens with 0 amount for the offer logic, since the logic can be the first in a chain and router needs to flush all
  ///@dev this function is also to be used when user deposits funds on the maker contract
  function pushAndSupply(IERC20 token0, uint amount0, IERC20 token1, uint amount1) external onlyBound {
    require(TransferLib.transferTokenFrom(token0, msg.sender, address(this), amount0), "AavePrivateRouter/pushFailed");
    require(TransferLib.transferTokenFrom(token1, msg.sender, address(this), amount1), "AavePrivateRouter/pushFailed");
    Memoizer memory m;
    _repayThenDeposit(token0, address(this), balanceOf(token0, m));
    _repayThenDeposit(token1, address(this), balanceOf(token1, m));
  }

  // structs to avoir stack too deep in maxGettableUnderlying
  struct Underlying {
    uint ltv;
    uint liquidationThreshold;
    uint decimals;
    uint price;
  }

  ///@notice returns line of credit of `this` contract in the form of a pair (maxRedeem, maxBorrow) corresponding respectively
  ///to the max amount of `token` this contract can withdraw from the pool, and the max amount of `token` it can borrow in addition (after withdrawing `maxRedeem`)
  ///@param token the asset one wishes to get from the pool
  ///@param m the memoizer
  function maxGettableUnderlying(IERC20 token, Memoizer memory m) public view returns (uint, uint) {
    Underlying memory underlying; // asset parameters
    (
      underlying.ltv, // collateral factor for lending
      underlying.liquidationThreshold, // collateral factor for borrowing
      /*liquidationBonus*/
      ,
      underlying.decimals,
      /*reserveFactor*/
      ,
      /*emode_category*/
    ) = ReserveConfiguration.getParams(reserveData(token, m).configuration);

    // redeemPower = account.liquidationThreshold * account.collateral - account.debt
    uint redeemPower = (
      userAccountData(m).liquidationThreshold * userAccountData(m).collateral - userAccountData(m).debt * 10 ** 4
    ) / 10 ** 4;

    // max redeem capacity = account.redeemPower/ underlying.liquidationThreshold * underlying.price
    // unless account doesn't have enough collateral in asset token (hence the min())
    uint maxRedeemableUnderlying = (
      redeemPower // in 10**underlying.decimals
        * 10 ** underlying.decimals * 10 ** 4
    ) / (underlying.liquidationThreshold * assetPrice(token, m));

    maxRedeemableUnderlying =
      (maxRedeemableUnderlying < overlyingBalanceOf(token, m)) ? maxRedeemableUnderlying : overlyingBalanceOf(token, m);

    // computing max borrow capacity on the premisses that maxRedeemableUnderlying has been redeemed.
    // max borrow capacity = (account.borrowPower - (ltv*redeemed)) / underlying.ltv * underlying.price

    uint borrowPowerImpactOfRedeemInUnderlying = (maxRedeemableUnderlying * underlying.ltv) / 10 ** 4;

    uint borrowPowerInUnderlying = (userAccountData(m).borrowPower * 10 ** underlying.decimals) / assetPrice(token, m);

    if (borrowPowerImpactOfRedeemInUnderlying > borrowPowerInUnderlying) {
      // no more borrowPower left after max redeem operation
      return (maxRedeemableUnderlying, 0);
    }

    // max borrow power in underlying after max redeem has been withdrawn
    uint maxBorrowAfterRedeemInUnderlying = borrowPowerInUnderlying - borrowPowerImpactOfRedeemInUnderlying;

    return (maxRedeemableUnderlying, maxBorrowAfterRedeemInUnderlying);
  }

  ///@notice pulls tokens from the pool according to the following policy:
  /// * if this contract's balance already has `amount` tokens, then those tokens are transferred w/o calling the pool
  /// * otherwise, all tokens that can be withdrawn from this contract's account on the pool are withdrawn
  /// * if withdrawal is insufficient to match `amount` the missing tokens are borrowed
  /// * if pull is `strict` then only amount is sent to the calling maker contract, otherwise the totality of pulled funds are sent to maker
  ///@dev if `strict` is enabled, then either `amount` is sent to maker of the call reverts.
  ///@inheritdoc AbstractRouter
  function __pull__(IERC20 token, address, uint amount, bool strict) internal override returns (uint pulled) {
    Memoizer memory m;
    uint localBalance = balanceOf(token, m);
    if (amount > localBalance) {
      localBalance += _redeem(token, type(uint).max, address(this));
      if (amount > localBalance) {
        _borrow(token, amount - localBalance, address(this));
        localBalance = amount;
      }
    }
    pulled = strict ? amount : localBalance;
    require(TransferLib.transferToken(token, msg.sender, pulled), "AavePrivateRouter/pullFailed");
  }

  ///@inheritdoc AbstractRouter
  function __checkList__(IERC20 token, address reserveId) internal view override {
    // any reserveId passes the checklist since this router does not pull or push liquidity to it (but unknown reserveId will have 0 shares)
    reserveId;
    // we check that `token` is listed on AAVE
    require(checkAsset(token), "AavePooledRouter/tokenNotLendableOnAave");
    require( // required to supply or withdraw token on pool
    token.allowance(address(this), address(POOL)) > 0, "AavePooledRouter/hasNotApprovedPool");
  }

  ///@inheritdoc AbstractRouter
  function __activate__(IERC20 token) internal virtual override {
    _approveLender(token, type(uint).max);
  }

  ///@notice revokes pool approval for a certain asset. This router will no longer be able to deposit on AAVE Pool
  ///@param token the address of the asset whose approval must be revoked.
  function revokeLenderApproval(IERC20 token) external onlyAdmin {
    _approveLender(token, 0);
  }

  ///@notice prevents AAVE from using a certain asset as collateral for lending
  ///@param token the asset address
  function exitMarket(IERC20 token) external onlyAdmin {
    _exitMarket(token);
  }

  ///@notice re-allows AAVE to use certain assets as collateral for lending
  ///@dev market is automatically entered at first deposit
  ///@param tokens the asset addresses
  function enterMarket(IERC20[] calldata tokens) external onlyAdmin {
    _enterMarkets(tokens);
  }

  ///@notice allows AAVE manager to claim the rewards attributed to this router by AAVE
  ///@param assets the list of overlyings (aToken, debtToken) whose rewards should be claimed
  ///@dev if some rewards are eligible they are sent to `aaveManager`
  ///@return rewardList the addresses of the claimed rewards
  ///@return claimedAmounts the amount of claimed rewards
  function claimRewards(address[] calldata assets)
    external
    onlyAdmin
    returns (address[] memory rewardList, uint[] memory claimedAmounts)
  {
    return _claimRewards(assets, msg.sender);
  }

  ///@notice returns the amount of funds available to this contract, summing up redeem and borrow capacities
  ///@param token the asset whose availability is being checked
  function balanceOfReserve(IERC20 token, address) public view override returns (uint) {
    Memoizer memory m;
    (uint r, uint b) = maxGettableUnderlying(token, m);
    return (r + b);
  }
}
