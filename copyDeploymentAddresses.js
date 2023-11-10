const deployments = require("@mangrovedao/mangrove-deployments");
const fs = require("fs");
const path = require("path");
const config = require("./config");

if (!config.copyDeployments) {
  console.group(
    "Skipping copying deployments from the mangrove-deployments package.",
  );
  console.log("Set copyDeployments = true in config.js to enable copying.");
  console.log("Using addresses/deployed/*.json files as-is instead.");
  console.groupEnd();
}

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

// NB: Test token deployments are included in the context-addresses package,
// so they are not queried from mangrove-deployments.

// Construct the addresses object for each network
const contractsDeployments = [
  mangroveVersionDeployments,
  mgvOracleVersionDeployments,
  mgvReaderVersionDeployments,
].filter((x) => x !== undefined);
const deployedAddressesByNetwork = {}; // network name => { name: string, address: string }[]
function getOrCreateNetworkAddresses(networkId) {
  const networkName = networkNames[+networkId];
  let networkAddresses = deployedAddressesByNetwork[networkName];
  if (networkAddresses === undefined) {
    networkAddresses = [];
    deployedAddressesByNetwork[networkName] = networkAddresses;
  }
  return networkAddresses;
}

for (const contractDeployments of contractsDeployments) {
  for (const [networkId, networkDeployments] of Object.entries(
    contractDeployments.networkAddresses,
  )) {
    const networkAddresses = getOrCreateNetworkAddresses(networkId);
    networkAddresses.push({
      name:
        contractDeployments.deploymentName ?? contractDeployments.contractName,
      address: networkDeployments.primaryAddress,
    });
  }
}

// Replace the addresses files with the loaded deployment addresses
for (const networkName in deployedAddressesByNetwork) {
  let addressesToWrite = deployedAddressesByNetwork[networkName];
  const networkAddressesFilePath = path.join(
    __dirname,
    `./addresses/deployed/${networkName}.json`,
  );
  fs.writeFileSync(
    networkAddressesFilePath,
    JSON.stringify(addressesToWrite, null, 2),
  );
}
