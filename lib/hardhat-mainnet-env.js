// Add Ethereum environment to Hardhat Runtime Environment
extendEnvironment((hre) => {
  hre.env = require("./mainnet-env")(hre.ethers);
});
