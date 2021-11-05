// /* Test Mangrove's permit functionality */
//
//
// ! WARNING ! Currently nonfunctional, waiting for hardhat to implement eth_signTypedData_v4.
//
//
// To watch:
// https://github.com/nomiclabs/hardhat/issues/1199
//
// Run with
//   npx hardhat run scripts/deploy.js
// possibly prefixed with
//   HARDHAT_NETWORK=<network name from hardhat.config>
// if you want the deploy to persist somewhere
async function main() {
  const ethers = hre.ethers;

  const MgvSetup = await ethers.getContractFactory("MgvSetup");
  const mgvSetup = await MgvSetup.deploy();

  const TokenSetup = await ethers.getContractFactory("TokenSetup");
  const tokenSetup = await TokenSetup.deploy();

  const Permit = await ethers.getContractFactory("PermitHelper", {
    libraries: {
      MgvSetup: mgvSetup.address,
      TokenSetup: tokenSetup.address,
    },
  });

  const permit = await Permit.deploy({
    value: ethers.utils.parseUnits("1000", "ether"),
  });

  const mgvAddress = await permit.mgvAddress();
  const baseAddress = await permit.baseAddress();
  const quoteAddress = await permit.quoteAddress();

  const TestToken = await ethers.getContractFactory("TestToken");
  const quote = TestToken.attach(quoteAddress);
  await quote.approve(mgvAddress, ethers.utils.parseUnits("1", "ether"));

  /* hardhat ethers wrapper does not expose signTypedData so we get the raw object */
  /* see https://github.com/nomiclabs/hardhat/issues/1108 */
  const owner = await ethers.provider.getSigner();

  // Follow https://eips.ethereum.org/EIPS/eip-2612
  const domain = {
    name: "Mangrove",
    version: "1",
    chainId: 31337, // hardhat chainid
    verifyingContract: mgvAddress,
  };

  const types = {
    Permit: [
      { name: "base", type: "address" },
      { name: "quote", type: "address" },
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
      { name: "value", type: "uint256" },
      { name: "nonce", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
  };

  const value = ethers.utils.parseUnits("2", "ether");
  const deadline = Math.floor(Date.now() / 1000) + 3600;

  // The data to sign
  const data = {
    base: baseAddress,
    quote: quoteAddress,
    owner: await owner.getAddress(),
    spender: permit.address,
    value: value,
    nonce: 0,
    deadline: deadline,
  };

  /* Test: no allowance
   * ********************/
  await permit.no_allowance();

  /* Test: wrong permit
   * ********************/
  const fakeOwner = await ethers.provider.getSigner(1);
  const fakeRawSignature = await fakeOwner._signTypedData(domain, types, data);

  const fakeSignature = ethers.utils.splitSignature(fakeRawSignature);
  await permit.wrong_permit(
    data.value,
    data.deadline,
    fakeSignature.v,
    fakeSignature.r,
    fakeSignature.s
  );

  /* Test: right permit
   * ********************/
  const rawSignature = await owner._signTypedData(domain, types, data);
  const signature = ethers.utils.splitSignature(rawSignature);

  await permit.good_permit(
    data.value,
    data.deadline,
    signature.v,
    signature.r,
    signature.s
  );

  /* Test: expired permit
   * ********************/
  const data2 = Object.assign({}, data, { deadline: 0 });
  rawSignature2 = await owner._signTypedData(domain, types, data2);
  signature2 = ethers.utils.splitSignature(rawSignature2);

  await permit.expired_permit(
    data2.value,
    data2.deadline,
    signature.v,
    signature.r,
    signature.s
  );
}

main()
  .then(() => {
    console.info("OK. No revert occurred.");
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
