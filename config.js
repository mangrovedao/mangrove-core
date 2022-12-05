// Contracts that should export their ABI only
exports.abi_exports = [
  "Mangrove",
  "MgvReader",
  "MgvCleaner",
  "MgvOracle",
  "SimpleTestMaker",
  "TestToken",
  "IERC20",
  "MangroveOrder",
  "MangroveOrderEnriched",
  "AbstractRouter",
  "AaveDeepRouter",
  "AaveV3Module",
  "ICreditDelegationToken",
  "ILiquidityProvider",
  "AccessControlled",
];

// Contracts that should export their ABI + bytecode
exports.full_exports = ["OfferForwarder", "OfferMaker", "SimpleTestMaker"];
