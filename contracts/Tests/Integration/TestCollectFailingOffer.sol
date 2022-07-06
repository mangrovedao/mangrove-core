// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;
pragma abicoder v2;
import "../Toolbox/TestUtils.sol";

library TestCollectFailingOffer {
  struct TestVars {
    AbstractMangrove mgv;
    uint failingOfferId;
    MakerDeployer makers;
    TestTaker taker;
    TestToken base;
    TestToken quote;
  }

  function run(
    TestUtils.Balances storage balances,
    mapping(uint => mapping(TestUtils.Info => uint)) storage offers,
    TestVars memory vars
  ) external {
    // executing failing offer
    try vars.taker.takeWithInfo(vars.failingOfferId, 0.5 ether) returns (
      bool success,
      uint takerGot,
      uint takerGave,
      uint,
      uint
    ) {
      // take should return false not throw
      TestEvents.check(!success, "Failer should fail");
      TestEvents.eq(takerGot, 0, "Failed offer should declare 0 takerGot");
      TestEvents.eq(takerGave, 0, "Failed offer should declare 0 takerGave");
      // failingOffer should have been removed from Mgv
      {
        TestEvents.check(
          !vars.mgv.isLive(
            vars.mgv.offers(
              address(vars.base),
              address(vars.quote),
              vars.failingOfferId
            )
          ),
          "Failing offer should have been removed from Mgv"
        );
      }
      uint provision = TestUtils.getProvision(
        vars.mgv,
        address(vars.base),
        address(vars.quote),
        offers[vars.failingOfferId][TestUtils.Info.gasreq]
      );
      uint returned = vars.mgv.balanceOf(address(vars.makers.getMaker(0))) -
        balances.makersBalanceWei[0];
      TestEvents.eq(
        address(vars.mgv).balance,
        balances.mgvBalanceWei - (provision - returned),
        "Mangrove has not send the correct amount to taker"
      );
    } catch (bytes memory errorMsg) {
      string memory err = abi.decode(errorMsg, (string));
      TestEvents.fail(err);
    }
  }
}
