// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.7.0;
pragma abicoder v2;
import "../Toolbox/TestUtils.sol";

library TestCollectFailingOffer {
  function run(
    TestUtils.Balances storage balances,
    mapping(uint => mapping(TestUtils.Info => uint)) storage offers,
    AbstractMangrove mgv,
    uint failingOfferId,
    MakerDeployer makers,
    TestTaker taker,
    TestToken base,
    TestToken quote
  ) external {
    // executing failing offer
    try taker.takeWithInfo(failingOfferId, 0.5 ether) returns (
      bool success,
      uint takerGot,
      uint takerGave
    ) {
      // take should return false not throw
      TestEvents.check(!success, "Failer should fail");
      TestEvents.eq(takerGot, 0, "Failed offer should declare 0 takerGot");
      TestEvents.eq(takerGave, 0, "Failed offer should declare 0 takerGave");
      // failingOffer should have been removed from Mgv
      {
        TestEvents.check(
          !mgv.isLive(
            mgv.offers(address(base), address(quote), failingOfferId)
          ),
          "Failing offer should have been removed from Mgv"
        );
      }
      uint provision = TestUtils.getProvision(
        mgv,
        address(base),
        address(quote),
        offers[failingOfferId][TestUtils.Info.gasreq]
      );
      uint returned = mgv.balanceOf(address(makers.getMaker(0))) -
        balances.makersBalanceWei[0];
      TestEvents.eq(
        address(mgv).balance,
        balances.mgvBalanceWei - (provision - returned),
        "Mangrove has not send the correct amount to taker"
      );
    } catch (bytes memory errorMsg) {
      string memory err = abi.decode(errorMsg, (string));
      TestEvents.fail(err);
    }
  }
}
