const deployments = require("@mangrovedao/mangrove-deployments");
const fs = require("fs");
const path = require("path");

// FIXME: Move most of this logic into the mangrove-deployments package

// FIXME: This is a hack to get the network names because the addresses files use non-canonical network names
const networkNames = {
  1: "mainnet",
  5: "goerli",
  137: "matic",
  42161: "arbitrum",
  80001: "maticmum",
};

// Get the latest deployments
// FIXME: It should be possible to choose other versions
const mangroveVersionDeployments = deployments.getMangroveVersionDeployments({
  released: undefined,
});
const mgvOracleVersionDeployments = deployments.getMgvOracleVersionDeployments({
  released: undefined,
});
const mgvReaderVersionDeployments = deployments.getMgvReaderVersionDeployments({
  released: undefined,
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
];
const deployedAddresses = {}; // network name => { name: string, address: string }[]
// Iterate over each contract deployment and add the addresses to the deployedAddresses object
for (const contractDeployments of contractsDeployments) {
  for (const key in contractDeployments.networkAddresses) {
    let networkDeployments = contractDeployments.networkAddresses[key];
    const networkId = networkNames[key];
    let networkAddresses = deployedAddresses[networkId];
    if (networkAddresses === undefined) {
      networkAddresses = [];
      deployedAddresses[networkId] = networkAddresses;
    }
    networkAddresses.push({
      name:
        contractDeployments.deploymentName ?? contractDeployments.contractName,
      address: networkDeployments.primaryAddress,
    });
  }
}

// Merge two lists of addresses, letting the second list override the first for any duplicate names
function mergeAddressLists(list1, list2) {
  // Create a copy of the second list
  const mergedList = [...list2];

  // Add items from the first list only if they don't exist in the second list
  list1.forEach((obj1) => {
    if (!list2.some((obj2) => obj2.name == obj1.name)) {
      mergedList.push(obj1);
    }
  });

  return mergedList;
}

// Update the addresses files with the loaded deployment addresses
for (const networkName in deployedAddresses) {
  let addressesToWrite = deployedAddresses[networkName];
  const networkAddressesFileName = `./addresses/deployed/${networkName}.json`;
  const networkAddressesFilePath = path.join(
    __dirname,
    networkAddressesFileName,
  );
  if (fs.existsSync(networkAddressesFilePath)) {
    const existingNetworkAddresses = require(networkAddressesFileName);
    addressesToWrite = mergeAddressLists(
      existingNetworkAddresses,
      addressesToWrite,
    );
  }
  fs.writeFileSync(
    networkAddressesFilePath,
    JSON.stringify(addressesToWrite, null, 2),
  );
}
