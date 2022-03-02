// wants/gives for successful offer
OFFER1_WANTS = 1;
OFFER1_GIVES = 1;
// wants/gives for failing offer
OFFER2_WANTS = 1;
OFFER2_GIVES = 1;

module.exports = async (hre) => {
  const ethers = hre.ethers;
  const deployer = (await hre.getNamedAccounts()).deployer;
  const signer = await ethers.getSigner(deployer);

  const big = (amount) => {
    return ethers.BigNumber.from(10).pow(18).mul(amount);
  };

  const mgv = await ethers.getContract("Mangrove", signer);
  const tokenA = await ethers.getContract("TokenA", signer);
  const tokenB = await ethers.getContract("TokenB", signer);
  const maker = await ethers.getContract("TestMaker", signer);

  console.log("Activating Token A/B market");
  await mgv.activate(tokenA.address, tokenB.address, 0, 0, 0);
  await mgv.activate(tokenB.address, tokenA.address, 0, 0, 0);

  await hre.deployments.deploy("TestMaker1", {
    log: true,
    contract: "TestMaker",
    from: deployer,
    args: [mgv.address, tokenA.address, tokenB.address],
  });

  const maker1 = await ethers.getContract("TestMaker1", signer);

  await hre.deployments.deploy("TestMaker2", {
    log: true,
    contract: "TestMaker",
    from: deployer,
    args: [mgv.address, tokenA.address, tokenB.address],
  });

  const maker2 = await ethers.getContract("TestMaker2", signer);

  console.log("Minting Token A for maker{1,2}");
  await tokenA.mint(maker1.address, big(10));
  await tokenA.mint(maker2.address, big(10));

  console.log("Giving native tokens to maker{1,2}");
  await signer.sendTransaction({
    to: maker1.address,
    value: big(2),
  });

  const tx = await signer.sendTransaction({
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
