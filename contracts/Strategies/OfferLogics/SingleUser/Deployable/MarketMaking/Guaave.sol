// SPDX-License-Identifier:	BSD-2-Clause

// Guaave.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;
import "./Mango/Mango.sol";
import "./GuaaveStorage.sol";
import "contracts/Strategies/Modules/aave/v3/AaveModule.sol";

/** Extension of Mango market maker with optimized yeilds on AAVE */
/** outbound/inbound token buffers are the base/quote treasuries (possibly EOA) */
/** aTokens should be the custody of `Guaava` */

contract Guaave is Mango, AaveV3Module {
  // Market on which Guaave will be acting
  address immutable BASE;
  address immutable QUOTE;

  struct MMoptions {
    uint base_0;
    uint quote_0;
    uint nslots;
    uint delta;
  }

  struct AaveOptions {
    address addressesProvider;
    uint interestRateMode;
  }

  event IncreaseBuffer(address indexed token, uint amount);
  event DecreaseBuffer(address indexed token, uint amount);

  constructor(
    address payable mgv,
    address base,
    address quote,
    MMoptions memory mango_args,
    AaveOptions memory aave_args,
    address caller
  )
    Mango(
      mgv,
      base,
      quote,
      mango_args.base_0,
      mango_args.quote_0,
      mango_args.nslots,
      mango_args.delta,
      caller
    )
    AaveV3Module(aave_args.addressesProvider, 0, aave_args.interestRateMode)
  {
    BASE = base;
    QUOTE = quote;
    // setting base and quote treasury to `this` to save transfer gas
    setGasreq(700_000);
    // Approving lender for base and quote transfer in order to be able to mint
    _approveLender(IEIP20(base), type(uint).max);
    _approveLender(IEIP20(quote), type(uint).max);
    // approve Mangrove to pull funds during trade in order to pay takers
    approveMangrove(quote, type(uint).max);
    approveMangrove(base, type(uint).max);
  }

  function set_buffer(bool base, uint buffer) external onlyAdmin {
    GuaaveStorage.Layout storage st = GuaaveStorage.get_storage();
    if (base) {
      st.base_put_threshold = buffer;
    } else {
      st.quote_put_threshold = buffer;
    }
  }

  // returns the target buffer level of `token` and the address of the treasury where the buffer is held
  function token_buffer_data(IEIP20 token)
    internal
    view
    returns (uint, address)
  {
    GuaaveStorage.Layout storage st = GuaaveStorage.get_storage();
    if (address(token) == BASE) {
      return (st.base_put_threshold, get_treasury({base: true}));
    } else {
      return (st.quote_put_threshold, get_treasury({base: false}));
    }
  }

  function __get__(uint amount, ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    address outbound_treasury = (order.outbound_tkn == BASE)
      ? get_treasury({base: true})
      : get_treasury({base: false});
    // if treasury is below target buffer, redeem on lender
    uint outbound_tkn_current_buffer = IEIP20(order.outbound_tkn).balanceOf(
      outbound_treasury
    );
    if (outbound_tkn_current_buffer < order.wants) {
      // redeems as many outbound tokens as `this` contract has overlyings.
      // redeem is deposited on the treasury of `outbound_tkn`
      uint redeemed = _redeem({
        token: IEIP20(order.outbound_tkn),
        amount: type(uint).max,
        to: outbound_treasury
      });
      outbound_tkn_current_buffer += redeemed;
      emit IncreaseBuffer(order.outbound_tkn, redeemed);
    }
    // Mango __get__ fetches outbound tokens from treasury
    return super.__get__(amount, order);
  }

  function maintain_token_buffer_level(IEIP20 token) internal {
    (uint tkn_buffer_target, address tkn_treasury) = token_buffer_data(token);
    uint current_buffer = token.balanceOf(tkn_treasury);
    if (current_buffer > tkn_buffer_target) {
      // pulling funds from the treasury to deposit them on Aaave
      uint amount = current_buffer - tkn_buffer_target;
      require(
        transferFromERC(token, tkn_treasury, address(this), amount),
        "Guaave/maintainBuffer/transferFail"
      );
      repayThenDeposit(token, amount);
      //_mint({token: token, amount: amount, onBehalf: address(this)});
      emit DecreaseBuffer(address(token), amount);
    }
  }

  // NB no specific __put__ needed as inbound tokens are deposited on treasury by `Mango__put__` and will be moved to lender during posthook
  function __posthookSuccess__(ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (bool)
  {
    // if `outbound_tkn` was fetched on lender during trade, buffer might be overfilled
    maintain_token_buffer_level(IEIP20(order.outbound_tkn));
    // since buffer has received `inbound_tkn` it might also be overfilled
    maintain_token_buffer_level(IEIP20(order.inbound_tkn));
    return super.__posthookSuccess__(order);
  }

  function redeem(
    IEIP20 token,
    uint amount,
    address to
  ) public mgvOrAdmin returns (uint) {
    require(to != address(0), "Guaave/redeem/0xAddress");
    return _redeem(token, amount, to);
  }

  function borrow(
    IEIP20 token,
    uint amount,
    address onBehalf
  ) public mgvOrAdmin {
    _borrow(token, amount, onBehalf);
  }

  function repay(
    IEIP20 token,
    uint amount,
    address onBehalf
  ) public mgvOrAdmin {
    _repay(token, amount, onBehalf);
  }

  function mint(
    IEIP20 token,
    uint amount,
    address onBehalf
  ) public mgvOrAdmin {
    _mint(token, amount, onBehalf);
  }

  // rewards claiming.
  // may use `SingleUser.redeemToken` to move collected tokens afterwards
  function claimRewards(
    IRewardsControllerIsh rewardsController,
    address[] calldata assets
  )
    public
    mgvOrAdmin
    returns (address[] memory rewardsList, uint[] memory claimedAmounts)
  {
    return _claimRewards(rewardsController, assets);
  }
}
