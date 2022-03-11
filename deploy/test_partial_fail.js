/**
 * This script allows you to posts two offers (with one that fails) on market.
 * Its goal is to reproduce on the front side the behavior of a transaction where an offer is eaten and another offer reverts.
 *
 * This script has "TestingSetup" as dependency, which means that this script will be executeed after the whole Mangrove ecosystem is deployed and freshly installed.
 *
 * By running this script you'll be able to interact a fresh local chain containing Mangrove contracts.
 */

// wants/gives for successful offer
OFFER1_WANTS = 1;
OFFER1_GIVES = 1;
// wants/gives for failing offer
OFFER2_WANTS = 1;
OFFER2_GIVES = 1;

const {
  TEST_TAKER_WALLET_ADDRESS: TAKER_WALLET_ADDRESS,
  TEST_TOKEN_A: TOKEN_A = "TokenA",
  TEST_TOKEN_B: TOKEN_B = "TokenB",
} = process.env;

module.exports = async (hre) => {
  if (!TAKER_WALLET_ADDRESS)
    throw Error(
      "You must provide your taker wallet address in order to provision it for UI testing"
    );
  const ethers = hre.ethers;
  const deployer = (await hre.getNamedAccounts()).deployer;
  const signer = await ethers.getSigner(deployer);

  const big = (amount) => {
    return ethers.BigNumber.from(10).pow(18).mul(amount);
  };

  const mgv = await ethers.getContract("Mangrove", signer);
  const tokenA = await ethers.getContract(TOKEN_A, signer);
  const tokenB = await ethers.getContract(TOKEN_B, signer);

  console.log("Activating Token A/B market");
  await mgv.activate(tokenA.address, tokenB.address, 0, 0, 0);
  await mgv.activate(tokenB.address, tokenA.address, 0, 0, 0);

  await hre.deployments.deploy("TestMaker1", {
    log: true,
    contract: "TestMaker",
    from: deployer,
    args: [mgv.address, tokenA.address, tokenB.address],
  });

  await hre.deployments.deploy("TestMaker2", {
    log: true,
    contract: "TestMaker",
    from: deployer,
    args: [mgv.address, tokenA.address, tokenB.address],
  });

  console.log(`Minting ${TOKEN_A} for taker`);
  await tokenA.mint(TAKER_WALLET_ADDRESS, big(10));
  console.log(`Minting ${TOKEN_B} for taker`);
  await tokenB.mint(TAKER_WALLET_ADDRESS, big(10));

  console.log("Giving native tokens to taker");
  await signer.sendTransaction({
    to: TAKER_WALLET_ADDRESS,
    value: big(2),
  });

  const maker1 = await ethers.getContract("TestMaker1", signer);
  const maker2 = await ethers.getContract("TestMaker2", signer);

  console.log(`Minting ${TOKEN_A} for maker{1,2}`);
  await tokenA.mint(maker1.address, big(10));
  await tokenA.mint(maker2.address, big(10));

  console.log("Giving native tokens to maker{1,2}");
  await signer.sendTransaction({
    to: maker1.address,
    value: big(2),
  });

  await signer.sendTransaction({
    to: maker2.address,
    value: big(2),
  });

  console.log("Maker{1,2} provisions mangrove");
  await maker1.provisionMgv(1);
  await maker2.provisionMgv(1);

  console.log("Configure Maker 2 to fail");
  await maker2.shouldRevert(true);

  const newOffer1 =
    maker1["newOfferWithFunding(uint256,uint256,uint256,uint256,uint256)"];
  const newOffer2 =
    maker2["newOfferWithFunding(uint256,uint256,uint256,uint256,uint256)"];

  console.log("Maker 1 posts offer");
  await newOffer1(big(OFFER1_WANTS), big(OFFER1_GIVES), 10000, 0, big(1));

  console.log("Maker 2 posts offer");
  await newOffer2(big(OFFER2_WANTS), big(OFFER2_GIVES), 10000, 0, big(1));
};

module.exports.tags = ["TestPartialFail"];
module.exports.dependencies = ["TestingSetup"];
