const hre = require("hardhat");
const { ethers } = hre;

const HARDHAT_NETWORK_ID = "31337";

module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { deploy, log } = deployments;
  const namedAccounts = await getNamedAccounts();
  const { admin, feeRecipient, DAO } = namedAccounts;

  const mathLib = await deployments.get("MathLib");
  const safeMetaDataLib = await deployments.get("SafeMetadata");

  const deployResult = await deploy("ExchangeFactory", {
    from: admin,
    contract: "ExchangeFactory",
    args: [feeRecipient],
    libraries: {
      MathLib: mathLib.address,
      SafeMetadata: safeMetaDataLib.address,
    },
  });
  if (deployResult.newlyDeployed) {
    log(
      `contract ExchangeFactory deployed at ${deployResult.address} using ${deployResult.receipt.gasUsed} gas`
    );
    await hre.run('verify:verify', {
      address: deployResult.address,
      constructorArguments: [ feeRecipient ],
    })
    const networkId = await getChainId();
    const accounts = await ethers.getSigners();
    if (networkId !== HARDHAT_NETWORK_ID) {
      log(`Setting ExchangeFactory owner address to DAO ${DAO}`);
      const exchangeFactory = new ethers.Contract(
        deployResult.address,
        deployResult.abi,
        accounts[0]
      );
      await exchangeFactory.transferOwnership(DAO);
      log(`ExchangeFactory owner is now ${await exchangeFactory.owner()}`);
    }
  }
};
module.exports.tags = ["ExchangeFactory"];
module.exports.dependencies = ["MathLib", "SafeMetadata"];
