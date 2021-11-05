const getParams = require("../lib/testDeploymentParams");

module.exports = async (hre) => {
  for (const dep of await getParams()) {
    await hre.deployments.deploy(dep.name, {
      log: true,
      deterministicDeployment: true,
      ...dep.options,
    });
  }
};
module.exports.tags = ["TestingSetup"];
