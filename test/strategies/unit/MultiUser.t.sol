import "mgv_src/strategies/routers/SimpleRouter.sol";

// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;
import "./OfferLogic.t.sol";
import "mgv_src/strategies/multi_user/MultiMaker.sol";

contract MultiUserTest is OfferLogicTest {
  function setupMakerContract() internal virtual override prank(maker) {
    makerContract = new MultiMaker({_MGV: IMangrove($(mgv)), deployer: maker});
    // reserve (which is maker here) approves contract's router
    usdc.approve(address(makerContract.router()), type(uint).max);
    weth.approve(address(makerContract.router()), type(uint).max);
  }
}
