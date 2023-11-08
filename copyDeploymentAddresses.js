const deployments = require("@mangrovedao/mangrove-deployments");
const fs = require("fs");
const path = require("path");
const config = require("./config");

// This is a hack to get the network names because the addresses
// file names use non-canonical network names from ethers.js
const networkNames = {
  1: "mainnet",
  5: "goerli",
  137: "matic",
  42161: "arbitrum",
  80001: "maticmum",
};

// Query deployments based on the configuration in config.js
const mangroveVersionDeployments = deployments.getMangroveVersionDeployments({
  version: config.coreDeploymentVersionRangePattern,
  released: config.coreDeploymentVersionReleasedFilter,
});
const mgvOracleVersionDeployments = deployments.getMgvOracleVersionDeployments({
  version: config.coreDeploymentVersionRangePattern,
  released: config.coreDeploymentVersionReleasedFilter,
});
const mgvReaderVersionDeployments = deployments.getMgvReaderVersionDeployments({
  version: config.coreDeploymentVersionRangePattern,
  released: config.coreDeploymentVersionReleasedFilter,
});
// FIXME: Duplicated deployment/contract names should be removed from the token deployments
const allTestErc20VersionDeployments =
  deployments.getAllTestErc20VersionDeployments({
    released: undefined,
  });

// Construct the addresses object for each network
const contractsDeployments = [
  mangroveVersionDeployments,
  mgvOracleVersionDeployments,
  mgvReaderVersionDeployments,
  ...allTestErc20VersionDeployments,
].filter((x) => x !== undefined);
const deployedAddresses = {}; // network name => { name: string, address: string }[]
// Iterate over each contract deployment and add the addresses to the deployedAddresses object
for (const contractDeployments of contractsDeployments) {
  for (const [networkId, networkDeployments] of Object.entries(
    contractDeployments.networkAddresses,
  )) {
    const networkName = networkNames[+networkId];
    let networkAddresses = deployedAddresses[networkName];
    if (networkAddresses === undefined) {
      networkAddresses = [];
      deployedAddresses[networkName] = networkAddresses;
    }
    networkAddresses.push({
      name:
        contractDeployments.deploymentName ?? contractDeployments.contractName,
      address: networkDeployments.primaryAddress,
    });
  }
}

// Replace the addresses files with the loaded deployment addresses
for (const networkName in deployedAddresses) {
  let addressesToWrite = deployedAddresses[networkName];
  const networkAddressesFilePath = path.join(
    __dirname,
    `./addresses/deployed/${networkName}.json`,
  );
  fs.writeFileSync(
    networkAddressesFilePath,
    JSON.stringify(addressesToWrite, null, 2),
  );
}
