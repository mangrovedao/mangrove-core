// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.7.0;
pragma abicoder v2;
import {ITaker, IMaker, MgvLib as DC, HasMgvEvents, IMgvMonitor} from "../../MgvLib.sol";
import "../../AbstractMangrove.sol";
import "../Toolbox/TestUtils.sol";
import "hardhat/console.sol";

/* TODO
 * dans makerExecute: check oracle price to see if I'm still in reasonable spread
 * don't sell all liquidity otherwie what is my price when I have 0 balance ? at least check that.
 */

contract MM1 {
  uint immutable sell_id;
  uint immutable buy_id;
  address immutable a_addr;
  address immutable b_addr;
  AbstractMangrove immutable mgv;

  /* This MM has 1 offer on each side of a book. After each take, it updates both offers.
     The new price is based on the midprice between each books, a base_spread,
     and the ratio of a/b inventories normalized by the current midprice. */

  constructor(
    AbstractMangrove _mgv,
    address _a_addr,
    address _b_addr
  ) payable {
    mgv = _mgv;
    a_addr = _a_addr;
    b_addr = _b_addr;

    _mgv.fund{value: 1 ether}(address(this));

    IERC20(_a_addr).approve(address(_mgv), 10000 ether);
    IERC20(_b_addr).approve(address(_mgv), 10000 ether);

    sell_id = _mgv.newOffer(_a_addr, _b_addr, 1, 1 ether, 40_000, 0, 0);
    buy_id = _mgv.newOffer(_b_addr, _a_addr, 1, 1 ether, 40_000, 0, 0);
  }

  function refresh() external {
    doMakerPosthook();
  }

  function makerExecute(DC.SingleOrder calldata) external returns (bytes32) {
    return "";
  }

  function makerPosthook(DC.SingleOrder calldata, DC.OrderResult calldata)
    external
  {
    doMakerPosthook();
  }

  /* Shifting to avoid overflows during intermediary steps */
  /* TODO use a fixed point library */
  uint constant SHF = 30;

  function doMakerPosthook() internal {
    // a&b must be k bits at most
    uint b = IERC20(b_addr).balanceOf(address(this)) >> SHF;
    uint a = IERC20(a_addr).balanceOf(address(this)) >> SHF;

    //console.log("b",b);
    //console.log("a",a);

    uint base_spread = 500; // base_spread is in basis points
    uint d_d = 10000; // delta = d_n / d_d

    // best offers
    uint best_sell_id = mgv.best(a_addr, b_addr);
    (DC.Offer memory best_sell, ) = mgv.offerInfo(a_addr, b_addr, best_sell_id);

    //console.log("initial bs.w",best_sell.wants);
    //console.log("initial bs.g",best_sell.gives);

    // if no offer on a/b pair
    if (
      best_sell_id == sell_id || (best_sell.wants == 0 && best_sell.gives == 0)
    ) {
      //console.log("no offer on a/b pair");
      best_sell.wants = b;
      best_sell.gives = a;
    } else {
      best_sell.wants = best_sell.wants >> SHF;
      best_sell.gives = best_sell.gives >> SHF;
    }

    //console.log("bs.w",best_sell.wants);
    //console.log("bs.g",best_sell.gives);

    uint best_buy_id = mgv.best(b_addr, a_addr);
    (DC.Offer memory best_buy, ) = mgv.offerInfo(b_addr, a_addr, best_buy_id);

    //console.log("initial bb.w",best_buy.wants);
    //console.log("initial bb.g",best_buy.gives);

    // if no offer on b/a pair
    if (best_buy_id == buy_id || (best_buy.wants == 0 && best_buy.gives == 0)) {
      //console.log("no offer on b/a pair");
      best_buy.wants = a;
      best_buy.gives = b;
    } else {
      best_buy.wants = best_buy.wants >> SHF;
      best_buy.gives = best_buy.gives >> SHF;
    }

    //console.log("bb.w",best_buy.wants);
    //console.log("bb.g",best_buy.gives);

    // average price numerator (same for buy&sell)
    // at most (96-SHF)*2+1 bits
    uint m_n = best_sell.wants *
      best_buy.wants +
      best_sell.gives *
      best_buy.gives;
    //console.log("m_n",m_n);

    uint d_n = 10000 + base_spread; // at most 14 bits

    /* SELL */
    /********/
    {
      // midprice of A in B is m_n/sell_m_d
      // at most (96-SHF)*2+1 bits
      uint sell_m_d = 2 * best_sell.gives * best_buy.wants;
      //console.log("sell_m_d",sell_m_d);

      uint sell_gives = a << SHF;
      //console.log("sell_gives",sell_gives);
      // normalized_BA_inv_ratio = b / (2 * a * b)
      // skew = 0.5 + inv/2 = (m_n * a + sell_m_d * b) / (2 * m_n * a)
      // sell_wants = delta * midprice * a * skew

      uint sell_wants_n = (d_n * (m_n * a + sell_m_d * b)) << (3 * SHF);
      //console.log("sell_wants_n",sell_wants_n);
      uint sell_wants_d = (2 * sell_m_d * d_d) << (3 * SHF);
      //console.log("sell_wants_d",sell_wants_d);
      uint sell_wants = (sell_wants_n / sell_wants_d) << SHF;

      //console.log("sell_wants",sell_wants);
      //console.log("sell_gives",sell_gives);
      Display.log(sell_wants, sell_gives);

      mgv.updateOffer({
        outbound_tkn: a_addr,
        inbound_tkn: b_addr,
        wants: sell_wants,
        gives: sell_gives,
        gasreq: 400_000,
        gasprice: 0,
        pivotId: sell_id,
        offerId: sell_id
      });
    }

    /* BUY */
    /*******/

    uint buy_m_d = 2 * best_sell.wants * best_buy.gives;

    uint buy_gives = b << SHF;

    // buy_wants = buy_delta * buy_midprice * b * buy_skew;
    uint buy_wants_n = d_n * (m_n * b + buy_m_d * a);
    uint buy_wants_d = 2 * buy_m_d * d_d;
    uint buy_wants = (buy_wants_n / buy_wants_d) << SHF;

    mgv.updateOffer({
      outbound_tkn: b_addr,
      inbound_tkn: a_addr,
      wants: buy_wants,
      gives: buy_gives,
      gasreq: 400_000,
      gasprice: 0,
      pivotId: buy_id,
      offerId: buy_id
    });
  }
}
