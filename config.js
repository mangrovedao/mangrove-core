// Contracts that should export their ABI only
exports.abi_exports = [
  "Mangrove",
  "MgvReader",
  "MgvCleaner",
  "MgvOracle",
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
  "AbstractKandel",
  "Kandel",
  "AaveKandel",
  "AbstractKandelSeeder",
  "KandelSeeder",
  "AaveKandelSeeder",
];

// Contracts that should export their ABI + bytecode
exports.full_exports = ["OfferMaker", "SimpleTestMaker"];
