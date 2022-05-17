// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");


async function deployResolver() {
  const Resolver = await ethers.getContractFactory("Resolver");
  const resolver = await Resolver.deploy();
  return await resolver.deployed();
}

async function polygonScanVerify(contractAddress, args, contractPath) {
  await hre.run("verify:verify", {
    address: contractAddress,
    constructorArguments: args,
    contract: contractPath
  });
}


async function main() {
  const resolver = await deployResolver();
  console.log(`
    Resolver deployed at ${resolver.address}
  `);

  await polygonScanVerify(resolver.address, [], "contracts/Resolver.sol:Resolver");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });