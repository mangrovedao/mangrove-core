// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity ^0.8.15;

enum GasMode {
  VOID,
  CLAIMABLE
}

interface IGas {
  function readGasParams(address contractAddress) external view returns (uint, uint, uint, GasMode);
  function setGasMode(address contractAddress, GasMode mode) external;
  function claimGasAtMinClaimRate(address contractAddress, address recipient, uint minClaimRateBips)
    external
    returns (uint);
  function claimAll(address contractAddress, address recipient) external returns (uint);
  function claimMax(address contractAddress, address recipient) external returns (uint);
  function claim(address contractAddress, address recipient, uint gasToClaim, uint gasSecondsToConsume)
    external
    returns (uint);
}

contract Gas is IGas {
  address public immutable admin;

  // Blast.sol --> controls all dAPP accesses to Gas.sol
  address public immutable blastConfigurationContract;

  // BaseFeeVault.sol -> fees from gas claims directed here
  address public immutable blastFeeVault;

  // zero claim rate in bps -> percent of gas user is able to claim
  // without consuming any gas seconds
  uint public zeroClaimRate; // bps

  // base claim rate in bps -> percent of gas user is able to claim
  // by consuming base gas seconds
  uint public baseGasSeconds;
  uint public baseClaimRate; // bps

  // ceil claim rate in bps -> percent of gas user is able to claim
  // by consuming ceil gas seconds or more
  uint public ceilGasSeconds;
  uint public ceilClaimRate; // bps

  /**
   * @notice Constructs the blast gas contract.
   * @param _admin The address of the admin.
   * @param _blastConfigurationContract The address of the Blast configuration contract.
   * @param _blastFeeVault The address of the Blast fee vault.
   * @param _zeroClaimRate The zero claim rate.
   * @param _baseGasSeconds The base gas seconds.
   * @param _baseClaimRate The base claim rate.
   * @param _ceilGasSeconds The ceiling gas seconds.
   * @param _ceilClaimRate The ceiling claim rate.
   */
  constructor(
    address _admin,
    address _blastConfigurationContract,
    address _blastFeeVault,
    uint _zeroClaimRate,
    uint _baseGasSeconds,
    uint _baseClaimRate,
    uint _ceilGasSeconds,
    uint _ceilClaimRate
  ) {
    require(_zeroClaimRate < _baseClaimRate, "zero claim rate must be < base claim rate");
    require(_baseClaimRate < _ceilClaimRate, "base claim rate must be < ceil claim rate");
    require(_baseGasSeconds < _ceilGasSeconds, "base gas seconds must be < ceil gas seconds");
    require(_baseGasSeconds > 0, "base gas seconds must be > 0");
    // admin vars
    admin = _admin;
    blastConfigurationContract = _blastConfigurationContract;
    blastFeeVault = _blastFeeVault;
    zeroClaimRate = _zeroClaimRate;
    baseGasSeconds = _baseGasSeconds;
    baseClaimRate = _baseClaimRate;
    ceilGasSeconds = _ceilGasSeconds;
    ceilClaimRate = _ceilClaimRate;
  }

  /**
   * @notice Allows only the admin to call a function
   */
  modifier onlyAdmin() {
    require(msg.sender == admin, "Caller is not the admin");
    _;
  }
  /**
   * @notice Allows only the Blast Configuration Contract to call a function
   */

  modifier onlyBlastConfigurationContract() {
    require(msg.sender == blastConfigurationContract, "Caller must be blast configuration contract");
    _;
  }

  /**
   * @notice Allows the admin to update the parameters
   * @param _zeroClaimRate The new zero claim rate
   * @param _baseGasSeconds The new base gas seconds
   * @param _baseClaimRate The new base claim rate
   * @param _ceilGasSeconds The new ceiling gas seconds
   * @param _ceilClaimRate The new ceiling claim rate
   */
  function updateAdminParameters(
    uint _zeroClaimRate,
    uint _baseGasSeconds,
    uint _baseClaimRate,
    uint _ceilGasSeconds,
    uint _ceilClaimRate
  ) external onlyAdmin {
    require(_zeroClaimRate < _baseClaimRate, "zero claim rate must be < base claim rate");
    require(_baseClaimRate < _ceilClaimRate, "base claim rate must be < ceil claim rate");
    require(_baseGasSeconds < _ceilGasSeconds, "base gas seconds must be < ceil gas seconds");
    require(_baseGasSeconds > 0, "base gas seconds must be > 0");

    zeroClaimRate = _zeroClaimRate;
    baseGasSeconds = _baseGasSeconds;
    baseClaimRate = _baseClaimRate;
    ceilGasSeconds = _ceilGasSeconds;
    ceilClaimRate = _ceilClaimRate;
  }

  /**
   * @notice Allows the admin to claim the gas of any address
   * @param contractAddress The address of the contract
   * @return The amount of ether balance claimed
   */
  function adminClaimGas(address contractAddress) external onlyAdmin returns (uint) {
    (, uint etherBalance,,) = readGasParams(contractAddress);
    _updateGasParams(contractAddress, 0, 0, GasMode.VOID);
    payable(blastFeeVault).transfer(etherBalance);
    return etherBalance;
  }
  /**
   * @notice Allows an authorized user to set the gas mode for a contract via the BlastConfigurationContract
   * @param contractAddress The address of the contract
   * @param mode The new gas mode for the contract
   */

  function setGasMode(address contractAddress, GasMode mode) external onlyBlastConfigurationContract {
    // retrieve gas params
    (uint etherSeconds, uint etherBalance,,) = readGasParams(contractAddress);
    _updateGasParams(contractAddress, etherSeconds, etherBalance, mode);
  }

  /**
   * @notice Allows a user to claim gas at a minimum claim rate
   * @param contractAddress The address of the contract
   * @param recipientOfGas The address of the recipient of the gas
   * @param minClaimRateBips The minimum claim rate in basis points
   * @return The amount of gas claimed
   */
  function claimGasAtMinClaimRate(address contractAddress, address recipientOfGas, uint minClaimRateBips)
    public
    returns (uint)
  {
    (uint etherSeconds, uint etherBalance,,) = readGasParams(contractAddress);
    if (minClaimRateBips <= zeroClaimRate) {
      return claimAll(contractAddress, recipientOfGas);
    }

    // set minClaimRate to baseClaimRate in this case
    if (minClaimRateBips < baseClaimRate) {
      minClaimRateBips = baseClaimRate;
    }

    uint bipsDiff = minClaimRateBips - baseClaimRate;
    uint secondsDiff = ceilGasSeconds - baseGasSeconds;
    uint rateDiff = ceilClaimRate - baseClaimRate;
    uint minSecondsStaked = baseGasSeconds + (bipsDiff * secondsDiff / rateDiff);
    uint maxEtherClaimable = etherSeconds / minSecondsStaked;
    if (maxEtherClaimable > etherBalance) {
      maxEtherClaimable = etherBalance;
    }
    uint secondsToConsume = maxEtherClaimable * minSecondsStaked;
    return claim(contractAddress, recipientOfGas, maxEtherClaimable, secondsToConsume);
  }

  /**
   * @notice Allows a contract to claim all gas
   * @param contractAddress The address of the contract
   * @param recipientOfGas The address of the recipient of the gas
   * @return The amount of gas claimed
   */
  function claimAll(address contractAddress, address recipientOfGas) public returns (uint) {
    (uint etherSeconds, uint etherBalance,,) = readGasParams(contractAddress);
    return claim(contractAddress, recipientOfGas, etherBalance, etherSeconds);
  }

  /**
   * @notice Allows a contract to claim all gas at the highest possible claim rate
   * @param contractAddress The address of the contract
   * @param recipientOfGas The address of the recipient of the gas
   * @return The amount of gas claimed
   */
  function claimMax(address contractAddress, address recipientOfGas) public returns (uint) {
    return claimGasAtMinClaimRate(contractAddress, recipientOfGas, ceilClaimRate);
  }
  /**
   * @notice Allows a contract to claim a specified amount of gas, at a claim rate set by the number of gas seconds
   * @param contractAddress The address of the contract
   * @param recipientOfGas The address of the recipient of the gas
   * @param gasToClaim The amount of gas to claim
   * @param gasSecondsToConsume The amount of gas seconds to consume
   * @return The amount of gas claimed (gasToClaim - penalty)
   */

  function claim(address contractAddress, address recipientOfGas, uint gasToClaim, uint gasSecondsToConsume)
    public
    onlyBlastConfigurationContract
    returns (uint)
  {
    // retrieve gas params
    (uint etherSeconds, uint etherBalance,, GasMode mode) = readGasParams(contractAddress);

    // check validity requirements
    require(gasToClaim > 0, "must withdraw non-zero amount");
    require(gasToClaim <= etherBalance, "too much to withdraw");
    require(gasSecondsToConsume <= etherSeconds, "not enough gas seconds");

    // get claim rate
    (uint claimRate, uint gasSecondsToConsumeNormalized) = getClaimRateBps(gasSecondsToConsume, gasToClaim);

    // calculate tax
    uint userEther = gasToClaim * claimRate / 10_000;
    uint penalty = gasToClaim - userEther;

    _updateGasParams(contractAddress, etherSeconds - gasSecondsToConsumeNormalized, etherBalance - gasToClaim, mode);

    payable(recipientOfGas).transfer(userEther);
    payable(blastFeeVault).transfer(penalty);

    return userEther;
  }
  /**
   * @notice Calculates the claim rate in basis points based on gasSeconds, gasToClaim
   * @param gasSecondsToConsume The amount of gas seconds to consume
   * @param gasToClaim The amount of gas to claim
   * @return claimRate The calculated claim rate in basis points
   * @return gasSecondsToConsume The normalized gas seconds to consume (<= gasSecondsToConsume)
   */

  function getClaimRateBps(uint gasSecondsToConsume, uint gasToClaim) public view returns (uint, uint) {
    uint secondsStaked = gasSecondsToConsume / gasToClaim;
    if (secondsStaked < baseGasSeconds) {
      return (zeroClaimRate, 0);
    }
    if (secondsStaked > ceilGasSeconds) {
      uint gasToConsumeNormalized = gasToClaim * ceilGasSeconds;
      return (ceilClaimRate, gasToConsumeNormalized);
    }

    uint rateDiff = ceilClaimRate - baseClaimRate;
    uint secondsDiff = ceilGasSeconds - baseGasSeconds;
    uint secondsStakedDiff = secondsStaked - baseGasSeconds;
    uint additionalClaimRate = rateDiff * secondsStakedDiff / secondsDiff;
    uint claimRate = baseClaimRate + additionalClaimRate;
    return (claimRate, gasSecondsToConsume);
  }

  /**
   * @notice Reads the gas parameters for a given user
   * @param user The address of the user
   * @return etherSeconds The integral of ether over time (ether * seconds vested)
   * @return etherBalance The total ether balance for the user
   * @return lastUpdated The last updated timestamp for the user's gas parameters
   * @return mode The current gas mode for the user
   */
  function readGasParams(address user)
    public
    view
    returns (uint etherSeconds, uint etherBalance, uint lastUpdated, GasMode mode)
  {
    bytes32 paramsHash = keccak256(abi.encodePacked(user, "parameters"));
    bytes32 packedParams;
    // read params
    assembly {
      packedParams := sload(paramsHash)
    }

    // unpack params
    // - The first byte (most significant byte) represents the mode
    // - The next 12 bytes represent the etherBalance
    // - The following 15 bytes represent the etherSeconds
    // - The last 4 bytes (least significant bytes) represent the lastUpdated timestamp
    mode = GasMode(uint8(packedParams[0]));
    etherBalance = uint((packedParams << (1 * 8)) >> ((32 - 12) * 8));
    etherSeconds = uint((packedParams << ((1 + 12) * 8)) >> ((32 - 15) * 8));
    lastUpdated = uint((packedParams << ((1 + 12 + 15) * 8)) >> ((32 - 4) * 8));

    // update ether seconds
    etherSeconds = etherSeconds + etherBalance * (block.timestamp - lastUpdated);
  }

  /**
   * @notice Updates the gas parameters for a given contract address
   * @param contractAddress The address of the contract
   * @param etherSeconds The integral of ether over time (ether * seconds vested)
   * @param etherBalance The total ether balance for the contract
   */
  function _updateGasParams(address contractAddress, uint etherSeconds, uint etherBalance, GasMode mode) internal {
    if (etherBalance >= 1 << (12 * 8) || etherSeconds >= 1 << (15 * 8)) {
      revert("Unexpected packing issue due to overflow");
    }

    uint updatedTimestamp = block.timestamp; // Known to fit in 4 bytes

    bytes32 paramsHash = keccak256(abi.encodePacked(contractAddress, "parameters"));
    bytes32 packedParams;
    packedParams = (
      (bytes32(uint(mode)) << ((12 + 15 + 4) * 8)) // Shift mode to the most significant byte
        | (bytes32(etherBalance) << ((15 + 4) * 8)) // Shift etherBalance to start after 1 byte of mode
        | (bytes32(etherSeconds) << (4 * 8)) // Shift etherSeconds to start after mode and etherBalance
        | bytes32(updatedTimestamp)
    ); // Keep updatedTimestamp in the least significant bytes

    assembly {
      sstore(paramsHash, packedParams)
    }
  }
}
