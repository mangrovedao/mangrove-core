// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {AbstractRouter} from "../AbstractRouter.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {AaveMemoizer, ReserveConfiguration} from "./AaveMemoizer.sol";
import {IERC20} from "mgv_src/IERC20.sol";

contract AavePrivateRouter is AaveMemoizer, AbstractRouter {
  event LogAaveIncident(address indexed maker, address indexed asset, bytes32 aaveReason);

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

  ///@notice Moves assets to pool. If asset has any debt it repays the debt before depositing the residual
  ///@param token the asset to push to the pool
  ///@param amount the amount of asset
  ///@param m the memoizer
  ///@param noRevert whether the function should revert with AAVE or return the revert message
  function _toPool(IERC20 token, uint amount, Memoizer memory m, bool noRevert) internal returns (bytes32 reason) {
    if (amount == 0) {
      return bytes32(0);
    }
    if (debtBalanceOf(token, m) > 0) {
      uint repaid;
      (repaid, reason) = _repay(token, amount, address(this), noRevert);
      if (reason != bytes32(0)) {
        return reason;
      }
      amount -= repaid;
    }
    reason = _supply(token, amount, address(this), noRevert);
  }

  ///@notice deposits router-local balance of an asset on the AAVE pool
  ///@param token the address of the asset
  function flushBuffer(IERC20 token) external onlyBound {
    Memoizer memory m;
    _toPool(token, balanceOf(token, m), m, false);
  }

  ///@notice pushes each given token from the calling maker contract to this router, then supplies the whole router-local balance to AAVE
  ///@param token0 the first token to deposit
  ///@param amount0 the amount of `token0` to deposit
  ///@param token1 the second token to deposit, might by IERC20(address(0)) when making a single token deposit
  ///@param amount1 the amount of `token1` to deposit
  ///@dev an offer logic should call this instead of `flush` when it is the last posthook to be executed
  ///@dev this can be determined by checking during __lastLook__ whether the logic will trigger a withdraw from AAVE (this is the case if router's balance of token is empty)
  ///@dev this call be performed even for tokens with 0 amount for the offer logic, since the logic can be the first in a chain and router needs to flush all
  ///@dev this function is also to be used when user deposits funds on the maker contract
  ///@dev if repay/supply should fail, funds are left on the router's balance, therefore bound maker must implement a public withdraw function to recover these funds if needed
  function pushAndSupply(IERC20 token0, uint amount0, IERC20 token1, uint amount1) external onlyBound {
    require(TransferLib.transferTokenFrom(token0, msg.sender, address(this), amount0), "AavePrivateRouter/pushFailed");
    require(TransferLib.transferTokenFrom(token1, msg.sender, address(this), amount1), "AavePrivateRouter/pushFailed");
    Memoizer memory m0;
    Memoizer memory m1;

    bytes32 reason;
    if (address(token0) != address(0)) {
      reason = _toPool(token0, balanceOf(token0, m0), m0, true);
      if (reason != bytes32(0)) {
        emit LogAaveIncident(msg.sender, address(token0), reason);
      }
    }
    if (address(token1) != address(0)) {
      reason = _toPool(token1, balanceOf(token1, m1), m1, true);
      if (reason != bytes32(0)) {
        emit LogAaveIncident(msg.sender, address(token1), reason);
      }
    }
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
  function maxGettableUnderlying(IERC20 token, Memoizer memory m, bool withBorrow) public view returns (uint, uint) {
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

    if (!withBorrow) {
      return (maxRedeemableUnderlying, 0);
    }
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
  /// * if withdrawal is insufficient to match `amount` the missing tokens are borrowed.
  /// Note we do not borrow the full capacity as it would put this contract is a liquidatable state. A malicious offer in the same m.o could prevent the posthook to repay the debt via an possible manipulation of the pool's state using flashloans.
  /// * if pull is `strict` then only amount is sent to the calling maker contract, otherwise the totality of pulled funds are sent to maker
  ///@dev if `strict` is enabled, then either `amount` is sent to maker of the call reverts.
  ///@inheritdoc AbstractRouter
  function __pull__(IERC20 token, address, uint amount, bool strict) internal override returns (uint pulled) {
    Memoizer memory m;
    uint localBalance = balanceOf(token, m);
    if (amount > localBalance) {
      (uint maxWithdraw, uint maxBorrow) = maxGettableUnderlying(token, m, true);
      // trying to withdraw if asset is available on pool
      if (maxWithdraw > 0) {
        // withdrawing all that can be redeeemed from AAVE
        (uint withdrawn, bytes32 reason) = _redeem(token, maxWithdraw, address(this), true);
        if (reason == bytes32(0)) {
          // localBalance has possibly more than required amount now
          localBalance += withdrawn;
        } else {
          // failed to withdraw possibly because asset is used as collateral for borrow or pool is dry
          emit LogAaveIncident(msg.sender, address(token), reason);
        }
      }
      if (amount > localBalance && amount - localBalance <= maxBorrow) {
        // missing funds and able to borrow what's missing
        bytes32 reason = _borrow(token, amount - localBalance, address(this), true);
        if (reason != bytes32(0)) {
          // we failed to borrow missing amount
          // note we do not try to borrow a part of missing for gas reason
          emit LogAaveIncident(msg.sender, address(token), reason);
          // cannot get more from the pool than `localBalance`
          amount = localBalance;
        } else {
          // localBalance now has the full required amount
          localBalance = amount;
        }
      } else {
        // maxBorrow is not enough to redeem missing funds
        amount = localBalance;
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

  struct AssetBalances {
    uint local;
    uint onPool;
    uint debt;
    uint debitLine;
    uint creditLine;
  }

  function assetBalances(IERC20 token) public view returns (AssetBalances memory bal) {
    Memoizer memory m;
    bal.debt = debtBalanceOf(token, m);
    bal.local = balanceOf(token, m);
    bal.onPool = overlyingBalanceOf(token, m);
    (bal.debitLine, bal.creditLine) = maxGettableUnderlying(token, m, true);
  }

  ///@notice returns the amount of funds available to this contract, summing up redeem and borrow capacities
  ///@notice we ignore potential debt because redeem and borrow capacity already takes debt into account
  ///@dev this function is gas costly, better used off chain.
  ///@inheritdoc AbstractRouter
  function balanceOfReserve(IERC20 token, address) public view override returns (uint) {
    Memoizer memory m;
    (uint r, uint b) = maxGettableUnderlying(token, m, true);
    return (r + b);
  }

  ///@notice returns asset price in AAVE market base token units (e.g USD with 8 decimals)
  function assetPrice(IERC20 token) public view returns (uint) {
    Memoizer memory m;
    return assetPrice(token, m);
  }
}
