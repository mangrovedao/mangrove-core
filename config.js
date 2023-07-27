// Contracts that should export their ABI only
exports.abi_exports = [
  "Mangrove",
  "MgvReader",
  "MgvCleaner",
  "MgvOracle",
  "TestToken",
  "IERC20",
  "MangroveOrder",
  "AbstractRouter",
  "ICreditDelegationToken",
  "ILiquidityProvider",
  "IOfferLogic",
  "AccessControlled",
  "AbstractKandel",
  "GeometricKandel",
  "Kandel",
  "AaveKandel",
  "ShortKandel",
  "AavePrivateRouter",
  "AbstractKandelSeeder",
  "KandelSeeder",
  "AaveKandelSeeder",
];

// Contracts that should export their ABI + bytecode
exports.full_exports = ["OfferMaker", "SimpleTestMaker"];
