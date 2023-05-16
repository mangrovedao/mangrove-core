// SPDX-License-Identifier: ISC
/**
 * By using this software, you understand, acknowledge and accept that Tetu
 * and/or the underlying software are provided “as is” and “as available”
 * basis and without warranties or representations of any kind either expressed
 * or implied. Any use of this open source software released under the ISC
 * Internet Systems Consortium license is done at your own risk to the fullest
 * extent permissible pursuant to applicable law any and all liability as well
 * as all warranties, including any fitness for a particular purpose with respect
 * to Tetu and/or the underlying software and the use thereof are disclaimed.
 */

pragma solidity ^0.8.4;

interface ISmartVault {
  function DEPOSIT_FEE_DENOMINATOR() external view returns (uint);

  function LOCK_PENALTY_DENOMINATOR() external view returns (uint);

  function TO_INVEST_DENOMINATOR() external view returns (uint);

  function VERSION() external view returns (string memory);

  function active() external view returns (bool);

  function addRewardToken(address rt) external;

  function alwaysInvest() external view returns (bool);

  function availableToInvestOut() external view returns (uint);

  function changeActivityStatus(bool _active) external;

  function changeAlwaysInvest(bool _active) external;

  function changeDoHardWorkOnInvest(bool _active) external;

  function changePpfsDecreaseAllowed(bool _value) external;

  function changeProtectionMode(bool _active) external;

  function deposit(uint amount) external;

  function depositAndInvest(uint amount) external;

  function depositFeeNumerator() external view returns (uint);

  function depositFor(uint amount, address holder) external;

  function doHardWork() external;

  function doHardWorkOnInvest() external view returns (bool);

  function duration() external view returns (uint);

  function earned(address rt, address account) external view returns (uint);

  function earnedWithBoost(address rt, address account) external view returns (uint);

  function exit() external;

  function getAllRewards() external;

  function getAllRewardsAndRedirect(address owner) external;

  function getPricePerFullShare() external view returns (uint);

  function getReward(address rt) external;

  function getRewardTokenIndex(address rt) external view returns (uint);

  function initializeSmartVault(
    string memory _name,
    string memory _symbol,
    address _controller,
    address __underlying,
    uint _duration,
    bool _lockAllowed,
    address _rewardToken,
    uint _depositFee
  ) external;

  function lastTimeRewardApplicable(address rt) external view returns (uint);

  function lastUpdateTimeForToken(address) external view returns (uint);

  function lockAllowed() external view returns (bool);

  function lockPenalty() external view returns (uint);

  function notifyRewardWithoutPeriodChange(address _rewardToken, uint _amount) external;

  function notifyTargetRewardAmount(address _rewardToken, uint amount) external;

  function overrideName(string memory value) external;

  function overrideSymbol(string memory value) external;

  function periodFinishForToken(address) external view returns (uint);

  function ppfsDecreaseAllowed() external view returns (bool);

  function protectionMode() external view returns (bool);

  function rebalance() external;

  function removeRewardToken(address rt) external;

  function rewardPerToken(address rt) external view returns (uint);

  function rewardPerTokenStoredForToken(address) external view returns (uint);

  function rewardRateForToken(address) external view returns (uint);

  function rewardTokens() external view returns (address[] memory);

  function rewardTokensLength() external view returns (uint);

  function rewardsForToken(address, address) external view returns (uint);

  function setLockPenalty(uint _value) external;

  function setRewardsRedirect(address owner, address receiver) external;

  function setLockPeriod(uint _value) external;

  function setStrategy(address newStrategy) external;

  function setToInvest(uint _value) external;

  function stop() external;

  function strategy() external view returns (address);

  function toInvest() external view returns (uint);

  function underlying() external view returns (address);

  function underlyingBalanceInVault() external view returns (uint);

  function underlyingBalanceWithInvestment() external view returns (uint);

  function underlyingBalanceWithInvestmentForHolder(address holder) external view returns (uint);

  function underlyingUnit() external view returns (uint);

  function userBoostTs(address) external view returns (uint);

  function userLastDepositTs(address) external view returns (uint);

  function userLastWithdrawTs(address) external view returns (uint);

  function userLockTs(address) external view returns (uint);

  function userRewardPerTokenPaidForToken(address, address) external view returns (uint);

  function withdraw(uint numberOfShares) external;

  function withdrawAllToVault() external;

  function getAllRewardsFor(address rewardsReceiver) external;

  function lockPeriod() external view returns (uint);
}
