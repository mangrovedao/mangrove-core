// Run with
//   npx hardhat run scripts/deploy.js
// possibly prefixed with
//   HARDHAT_NETWORK=<network name from hardhat.config>
// if you want the deploy to persist somewhere
async function main() {
  const $e = hre.ethers;

  const [owner, addr1, addr2] = await $e.getSigners();
  console.log("owner", owner.address);
  //  const Lib = await $e.getContractFactory("DexLib");
  //  const dexLib = await DexLib.deploy();
  //  console.log("dexlib", dexLib.address);
  const Mangrove = await $e.getContractFactory("Mangrove");
  const mgv = await Mangrove.deploy(1, 1, 1, true);
  console.log("mgv", mgv);

  /* To activate for two tokens:
  const TestToken = await $e.getContractFactory("TestToken");
  const base = await TestToken.deploy(owner.address, "A", "$A");
  const quote = await TestToken.deploy(owner.address, "B", "$B");
  console.log("base", base.address);
  console.log("quote", quote.address);

  dex.setActive(base.address, quote.address, true);
  */
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
