// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.7.0;
import "../Toolbox/TestUtils.sol";

library TestCancelOffer {
  function run(
    TestUtils.Balances storage balances,
    mapping(uint => mapping(TestUtils.Info => uint)) storage offers,
    AbstractMangrove mgv,
    TestMaker wrongOwner,
    TestMaker maker,
    uint offerId,
    TestTaker, /* taker */
    TestToken base,
    TestToken quote
  ) external {
    try wrongOwner.retractOfferWithDeprovision(offerId) {
      TestEvents.fail("Invalid authorization to cancel order");
    } catch Error(string memory reason) {
      TestEvents.eq(reason, "mgv/cancelOffer/unauthorized", "Unexpected throw");
      try maker.retractOfferWithDeprovision(offerId) {
        maker.retractOfferWithDeprovision(0);
        uint provisioned = TestUtils.getProvision(
          mgv,
          address(base),
          address(quote),
          offers[offerId][TestUtils.Info.gasreq]
        );
        TestEvents.eq(
          mgv.balanceOf(address(maker)),
          balances.makersBalanceWei[offerId] + provisioned,
          "Incorrect returned provision to maker"
        );
      } catch {
        TestEvents.fail("Cancel order failed unexpectedly");
      }
    }
  }
}
