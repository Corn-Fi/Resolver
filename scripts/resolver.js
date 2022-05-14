// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const { ethers } = require("hardhat");
const hre = require("hardhat");
const Resolver = require("../artifacts/contracts/Resolver.sol/Resolver.json");
const { addresses } = require("./addresses");


async function fetchSigner() {
  const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY);
  const signer = wallet.connect(provider);
  console.log(`connected to ${signer.address}`);
  return signer;
}

// ----------------------------------------------------------------------------------

async function fetchContract(address, abi, signer) {
  const contract = new ethers.Contract(address, abi, signer);
  console.log(`loaded contract ${contract.address}`);
  return contract;
}

// ----------------------------------------------------------------------------------

async function findBestPathExactIn(fromToken, toToken, amountIn) {
  const signer = await fetchSigner();
  const resolver = await fetchContract(addresses.resolver, Resolver.abi, signer)
  const data = await resolver.findBestPathExactIn(fromToken, toToken, amountIn);
  return {
    "router": data[0],
    "path": data[1],
    "amountOut": data[2]
  }
}

// ----------------------------------------------------------------------------------

async function swapExactIn(router, amountIn, amountOutMin, path, to, deadline) {
  const signer = await fetchSigner();
  const resolver = await fetchContract(addresses.resolver, Resolver.abi, signer)
  return await resolver.swapExactIn(router, amountIn, amountOutMin, path, to, deadline);
}

// ----------------------------------------------------------------------------------
// ----------------------------------------------------------------------------------

async function main() {
  const out = await findBestPathExactIn("0x2791bca1f2de4661ed88a30c99a7a9449aa84174", "0x53e0bca35ec356bd5dddfebbd1fc0fd03fabad39", ethers.utils.parseUnits("10", 6));
  console.log(out);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
