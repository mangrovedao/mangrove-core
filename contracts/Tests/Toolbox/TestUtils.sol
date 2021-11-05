// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;
// Encode structs
pragma abicoder v2;

import "../Agents/TestTaker.sol";
import "../Agents/MakerDeployer.sol";
import "../Agents/TestMoriartyMaker.sol";
import "../Agents/TestToken.sol";

import {Display, Test as TestEvents} from "@giry/hardhat-test-solidity/test.sol";
import "../../InvertedMangrove.sol";
import "../../Mangrove.sol";
import {MgvPack as MP} from "../../MgvPack.sol";

library TestUtils {
  /* Various utilities */

  function uint2str(uint _i)
    internal
    pure
    returns (string memory _uintAsString)
  {
    if (_i == 0) {
      return "0";
    }
    uint j = _i;
    uint len;
    while (j != 0) {
      len++;
      j /= 10;
    }
    bytes memory bstr = new bytes(len);
    uint k = len - 1;
    while (_i != 0) {
      bstr[k--] = bytes1(uint8(48 + (_i % 10)));
      _i /= 10;
    }
    return string(bstr);
  }

  function append(string memory a, string memory b)
    internal
    pure
    returns (string memory)
  {
    return string(abi.encodePacked(a, b));
  }

  function append(
    string memory a,
    string memory b,
    string memory c
  ) internal pure returns (string memory) {
    return string(abi.encodePacked(a, b, c));
  }

  function append(
    string memory a,
    string memory b,
    string memory c,
    string memory d
  ) internal pure returns (string memory) {
    return string(abi.encodePacked(a, b, c, d));
  }

  function toEthUnits(uint w, string memory units)
    internal
    pure
    returns (string memory eth)
  {
    string memory suffix = append(" ", units);

    if (w == 0) {
      return (append("0", suffix));
    }
    uint i = 0;
    while (w % 10 == 0) {
      w = w / 10;
      i += 1;
    }
    if (i >= 18) {
      w = w * (10**(i - 18));
      return append(uint2str(w), suffix);
    } else {
      uint zeroBefore = 18 - i;
      string memory zeros = "";
      while (zeroBefore > 1) {
        zeros = append(zeros, "0");
        zeroBefore--;
      }
      return (append("0.", zeros, uint2str(w), suffix));
    }
  }

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
      (ML.Offer memory offer, ML.OfferDetail memory od) = mgv.offerInfo(
        base,
        quote,
        offerId
      );
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
      (ML.Offer memory ofr, ) = mgv.offerInfo(base, quote, offerId);
      console.log(
        "[offer %d] %s/%s",
        offerId,
        TestUtils.toEthUnits(ofr.wants, req_tk.symbol()),
        TestUtils.toEthUnits(ofr.gives, ofr_tk.symbol())
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

  /* Additional testing functions */

  function revertEq(string memory actual_reason, string memory expected_reason)
    internal
    returns (bool)
  {
    return TestEvents.eq(actual_reason, expected_reason, "wrong revert reason");
  }

  event TestNot0x(bool success, address addr);

  function not0x(address actual) internal returns (bool) {
    bool success = actual != address(0);
    emit TestNot0x(success, actual);
    return success;
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

  function getReason(bytes memory returnData)
    internal
    pure
    returns (string memory reason)
  {
    /* returnData for a revert(reason) is the result of
       abi.encodeWithSignature("Error(string)",reason)
       but abi.decode assumes the first 4 bytes are padded to 32
       so we repad them. See:
       https://github.com/ethereum/solidity/issues/6012
     */
    bytes memory pointer = abi.encodePacked(bytes28(0), returnData);
    uint len = returnData.length - 4;
    assembly {
      pointer := add(32, pointer)
      mstore(pointer, len)
    }
    reason = abi.decode(pointer, (string));
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
    (, bytes32 local) = mgv.config(base, quote);
    return ((price * MP.local_unpack_fee(local)) / 10000);
  }

  function getProvision(
    AbstractMangrove mgv,
    address base,
    address quote,
    uint gasreq
  ) internal view returns (uint) {
    (bytes32 glo_cfg, bytes32 loc_cfg) = mgv.config(base, quote);
    return ((gasreq +
      MP.local_unpack_overhead_gasbase(loc_cfg) +
      MP.local_unpack_offer_gasbase(loc_cfg)) *
      uint(MP.global_unpack_gasprice(glo_cfg)) *
      10**9);
  }

  function getProvision(
    AbstractMangrove mgv,
    address base,
    address quote,
    uint gasreq,
    uint gasprice
  ) internal view returns (uint) {
    (bytes32 glo_cfg, bytes32 loc_cfg) = mgv.config(base, quote);
    uint _gp;
    if (MP.global_unpack_gasprice(glo_cfg) > gasprice) {
      _gp = uint(MP.global_unpack_gasprice(glo_cfg));
    } else {
      _gp = gasprice;
    }
    return ((gasreq +
      MP.local_unpack_overhead_gasbase(loc_cfg) +
      MP.local_unpack_offer_gasbase(loc_cfg)) *
      _gp *
      10**9);
  }

  function getOfferInfo(
    AbstractMangrove mgv,
    address base,
    address quote,
    Info infKey,
    uint offerId
  ) internal view returns (uint) {
    (ML.Offer memory offer, ML.OfferDetail memory offerDetail) = mgv.offerInfo(
      base,
      quote,
      offerId
    );
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
      return offer.gasprice;
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
    (, ML.OfferDetail memory od) = mgv.offerInfo(base, quote, offerId);
    return od.maker;
  }
}

// Pretest libraries are for deploying large contracts independently.
// Otherwise bytecode can be too large. See EIP 170 for more on size limit:
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-170.md

library TokenSetup {
  function setup(string memory name, string memory ticker)
    public
    returns (TestToken)
  {
    return new TestToken(address(this), name, ticker);
  }
}

library MgvSetup {
  function deploy(address governance) public returns (AbstractMangrove mgv) {
    mgv = new Mangrove({
      governance: governance,
      gasprice: 40,
      gasmax: 1_000_000
    });
  }

  function invertedDeploy(address governance)
    public
    returns (AbstractMangrove mgv)
  {
    mgv = new InvertedMangrove({
      governance: governance,
      gasprice: 40,
      gasmax: 1_000_000
    });
  }

  function setup(TestToken base, TestToken quote)
    public
    returns (AbstractMangrove)
  {
    return setup(base, quote, false);
  }

  function setup(
    TestToken base,
    TestToken quote,
    bool inverted
  ) public returns (AbstractMangrove mgv) {
    TestUtils.not0x(address(base));
    TestUtils.not0x(address(quote));
    if (inverted) {
      mgv = invertedDeploy(address(this));
    } else {
      mgv = deploy(address(this));
    }
    mgv.activate(address(base), address(quote), 0, 100, 80_000, 20_000);
    mgv.activate(address(quote), address(base), 0, 100, 80_000, 20_000);
  }
}

library MakerSetup {
  function setup(
    AbstractMangrove mgv,
    address base,
    address quote,
    uint failer // 1 shouldFail, 2 shouldRevert
  ) external returns (TestMaker) {
    TestMaker tm = new TestMaker(mgv, IERC20(base), IERC20(quote));
    tm.shouldFail(failer == 1);
    tm.shouldRevert(failer == 2);
    return (tm);
  }

  function setup(
    AbstractMangrove mgv,
    address base,
    address quote
  ) external returns (TestMaker) {
    return new TestMaker(mgv, IERC20(base), IERC20(quote));
  }
}

library MakerDeployerSetup {
  function setup(
    AbstractMangrove mgv,
    address base,
    address quote
  ) external returns (MakerDeployer) {
    TestUtils.not0x(address(mgv));
    return (new MakerDeployer(mgv, base, quote));
  }
}

library TakerSetup {
  function setup(
    AbstractMangrove mgv,
    address base,
    address quote
  ) external returns (TestTaker) {
    TestUtils.not0x(address(mgv));
    return new TestTaker(mgv, IERC20(base), IERC20(quote));
  }
}
