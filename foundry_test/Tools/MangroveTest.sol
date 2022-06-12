// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;
import {Test2} from "./Test2.sol";
import {Utilities} from "./Utilities.sol";

import {TestTaker} from "mgv_src/Tests/Agents/TestTaker.sol";
import {TestMaker} from "mgv_src/Tests/Agents/TestMaker.sol";
import {MakerDeployer} from "mgv_src/Tests/Agents/MakerDeployer.sol";
import {TestMoriartyMaker} from "mgv_src/Tests/Agents/TestMoriartyMaker.sol";
import {TestToken} from "mgv_src/Tests/Agents/TestToken.sol";

import {AbstractMangrove, Mangrove} from "mgv_src/Mangrove.sol";
import {InvertedMangrove} from "mgv_src/InvertedMangrove.sol";
import {IERC20, MgvLib, P, HasMgvEvents, IMaker, ITaker, IMgvMonitor} from "mgv_src/MgvLib.sol";
import {console2 as console} from "forge-std/console2.sol";

contract MangroveTest is Utilities, Test2, HasMgvEvents {
  /* Log offer book */

  event OBState(
    address base,
    address quote,
    uint[] offerIds,
    uint[] wants,
    uint[] gives,
    address[] makerAddr,
    uint[] gasreqs
  );

  /** Two different OB logging methods.
   *
   *  `logOfferBook` will be well-interlaced with tests so you can easily see what's going on.
   *
   *  `printOfferBook` will survive reverts so you can log inside a reverting call.
   */

  /* Log OB with events and hardhat-test-solidity */
  function logOfferBook(
    AbstractMangrove mgv,
    address base,
    address quote,
    uint size
  ) internal {
    uint offerId = mgv.best(base, quote);

    uint[] memory wants = new uint[](size);
    uint[] memory gives = new uint[](size);
    address[] memory makerAddr = new address[](size);
    uint[] memory offerIds = new uint[](size);
    uint[] memory gasreqs = new uint[](size);
    uint c = 0;
    while ((offerId != 0) && (c < size)) {
      (P.OfferStruct memory offer, P.OfferDetailStruct memory od) = mgv
        .offerInfo(base, quote, offerId);
      wants[c] = offer.wants;
      gives[c] = offer.gives;
      makerAddr[c] = od.maker;
      offerIds[c] = offerId;
      gasreqs[c] = od.gasreq;
      offerId = offer.next;
      c++;
    }
    emit OBState(base, quote, offerIds, wants, gives, makerAddr, gasreqs);
  }

  /* Log OB with hardhat's console.log */
  function printOfferBook(
    AbstractMangrove mgv,
    address base,
    address quote
  ) internal view {
    uint offerId = mgv.best(base, quote);
    TestToken req_tk = TestToken(quote);
    TestToken ofr_tk = TestToken(base);

    console.log("-----Best offer: %d-----", offerId);
    while (offerId != 0) {
      (P.OfferStruct memory ofr, ) = mgv.offerInfo(base, quote, offerId);
      console.log(
        "[offer %d] %s/%s",
        offerId,
        toEthUnits(ofr.wants, req_tk.symbol()),
        toEthUnits(ofr.gives, ofr_tk.symbol())
      );
      // console.log(
      //   "(%d gas, %d to finish, %d penalty)",
      //   gasreq,
      //   minFinishGas,
      //   gasprice
      // );
      // console.log(name(makerAddr));
      offerId = ofr.next;
    }
    console.log("-----------------------");
  }

  event GasCost(string callname, uint value);

  function execWithCost(
    string memory callname,
    address addr,
    bytes memory data
  ) internal returns (bytes memory) {
    uint g0 = gasleft();
    (bool noRevert, bytes memory retdata) = addr.delegatecall(data);
    require(noRevert, "execWithCost should not revert");
    emit GasCost(callname, g0 - gasleft());
    return retdata;
  }

  struct Balances {
    uint mgvBalanceWei;
    uint mgvBalanceFees;
    uint takerBalanceA;
    uint takerBalanceB;
    uint takerBalanceWei;
    uint[] makersBalanceA;
    uint[] makersBalanceB;
    uint[] makersBalanceWei;
  }
  enum Info {
    makerWants,
    makerGives,
    nextId,
    gasreqreceive_on,
    gasprice,
    gasreq
  }

  function isEmptyOB(
    AbstractMangrove mgv,
    address base,
    address quote
  ) internal view returns (bool) {
    return mgv.best(base, quote) == 0;
  }

  function adminOf(AbstractMangrove mgv) internal view returns (address) {
    return mgv.governance();
  }

  function getFee(
    AbstractMangrove mgv,
    address base,
    address quote,
    uint price
  ) internal view returns (uint) {
    (, P.Local.t local) = mgv.config(base, quote);
    return ((price * local.fee()) / 10000);
  }

  function getProvision(
    AbstractMangrove mgv,
    address base,
    address quote,
    uint gasreq
  ) internal view returns (uint) {
    (P.Global.t glo_cfg, P.Local.t loc_cfg) = mgv.config(base, quote);
    return ((gasreq + loc_cfg.offer_gasbase()) *
      uint(glo_cfg.gasprice()) *
      10**9);
  }

  function getProvision(
    AbstractMangrove mgv,
    address base,
    address quote,
    uint gasreq,
    uint gasprice
  ) internal view returns (uint) {
    (P.Global.t glo_cfg, P.Local.t loc_cfg) = mgv.config(base, quote);
    uint _gp;
    if (glo_cfg.gasprice() > gasprice) {
      _gp = uint(glo_cfg.gasprice());
    } else {
      _gp = gasprice;
    }
    return ((gasreq + loc_cfg.offer_gasbase()) * _gp * 10**9);
  }

  function getOfferInfo(
    AbstractMangrove mgv,
    address base,
    address quote,
    Info infKey,
    uint offerId
  ) internal view returns (uint) {
    (P.OfferStruct memory offer, P.OfferDetailStruct memory offerDetail) = mgv
      .offerInfo(base, quote, offerId);
    if (!mgv.isLive(mgv.offers(base, quote, offerId))) {
      return 0;
    }
    if (infKey == Info.makerWants) {
      return offer.wants;
    }
    if (infKey == Info.makerGives) {
      return offer.gives;
    }
    if (infKey == Info.nextId) {
      return offer.next;
    }
    if (infKey == Info.gasreq) {
      return offerDetail.gasreq;
    } else {
      return offerDetail.gasprice;
    }
  }

  function hasOffer(
    AbstractMangrove mgv,
    address base,
    address quote,
    uint offerId
  ) internal view returns (bool) {
    return (getOfferInfo(mgv, base, quote, Info.makerGives, offerId) > 0);
  }

  function makerOf(
    AbstractMangrove mgv,
    address base,
    address quote,
    uint offerId
  ) internal view returns (address) {
    (, P.OfferDetailStruct memory od) = mgv.offerInfo(base, quote, offerId);
    return od.maker;
  }

  function setupToken(string memory name, string memory ticker)
    public
    returns (TestToken)
  {
    return new TestToken(address(this), name, ticker);
  }

  // low level mangrove deploy
  function deployMangrove(address governance)
    public
    returns (AbstractMangrove mgv)
  {
    mgv = new Mangrove({
      governance: governance,
      gasprice: 40,
      gasmax: 1_000_000
    });
  }

  // low level inverted mangrove deploy
  function deployInvertedMangrove(address governance)
    public
    returns (AbstractMangrove mgv)
  {
    mgv = new InvertedMangrove({
      governance: governance,
      gasprice: 40,
      gasmax: 1_000_000
    });
  }

  // setup normal mangrove
  function setupMangrove(TestToken base, TestToken quote)
    public
    returns (AbstractMangrove)
  {
    return setupMangrove(base, quote, false);
  }

  // setup mangrove, inverted or not
  function setupMangrove(
    TestToken base,
    TestToken quote,
    bool inverted
  ) public returns (AbstractMangrove mgv) {
    not0x(address(base));
    not0x(address(quote));
    if (inverted) {
      mgv = deployInvertedMangrove(address(this));
    } else {
      mgv = deployMangrove(address(this));
    }
    mgv.activate(address(base), address(quote), 0, 100, 20_000);
    mgv.activate(address(quote), address(base), 0, 100, 20_000);
  }

  // setup maker with failure params
  function setupMaker(
    AbstractMangrove mgv,
    address base,
    address quote,
    uint failer // 1 shouldFail, 2 shouldRevert
  ) public returns (TestMaker) {
    TestMaker tm = new TestMaker(mgv, IERC20(base), IERC20(quote));
    tm.shouldFail(failer == 1);
    tm.shouldRevert(failer == 2);
    return (tm);
  }

  // simple setup maker
  function setupMaker(
    AbstractMangrove mgv,
    address base,
    address quote
  ) public returns (TestMaker) {
    return new TestMaker(mgv, IERC20(base), IERC20(quote));
  }

  function setupMakerDeployer(
    AbstractMangrove mgv,
    address base,
    address quote
  ) public returns (MakerDeployer) {
    not0x(address(mgv));
    return (new MakerDeployer(mgv, base, quote));
  }

  function setupTaker(
    AbstractMangrove mgv,
    address base,
    address quote
  ) public returns (TestTaker) {
    not0x(address(mgv));
    return new TestTaker(mgv, IERC20(base), IERC20(quote));
  }
}
