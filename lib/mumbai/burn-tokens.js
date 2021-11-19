// This script burn a large amount of each of the below tokens.
const ethers = require("ethers");

const privateKey = process.env["PRIVATE_KEY"]; // EOA for signing the transaction - must have MATIC
const alchemyApiKey = process.env["ALCHEMY_API_KEY"];

const accountToBurn = "0x...";

const provider = new ethers.providers.AlchemyProvider(
  "maticmum",
  alchemyApiKey
);
const wallet = new ethers.Wallet(privateKey);
const signer = wallet.connect(provider);

const tokens = [
  {
    symbol: "MGV_ETH",
    amount: "1000",
    decimals: 18,
    address: "0xF1E3f817fF9CaAF7083a58C50a3c4a05f80dE565",
  },
  {
    symbol: "MGV_DAI",
    amount: "1000",
    decimals: 18,
    address: "0x94b4155EECEF4Ba5E24bA03F8a04da2789237435",
  },
  {
    symbol: "MGV_USD",
    amount: "1000",
    decimals: 6,
    address: "0x579ba1708e8E15c9D41143a3da4B8382831E0897",
  },
];

const burnToken = async ({ symbol, amount, decimals, address }) => {
  const contract = new ethers.Contract(
    address,
    ["function burn(address account, uint256 amount)"],
    signer
  );
  await contract
    .burn(accountToBurn, ethers.utils.parseUnits(amount, decimals))
    .then((tx) => tx.wait());
};

for (const token of tokens) {
  await burnToken(token);
}
