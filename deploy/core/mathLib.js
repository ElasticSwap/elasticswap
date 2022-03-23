const hre = require("hardhat");

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, log } = deployments;
  const namedAccounts = await getNamedAccounts();
  const { admin } = namedAccounts;

  const deployResult = await deploy("MathLib", {
    from: admin,
    contract: "MathLib",
    args: [],
  });
  if (deployResult.newlyDeployed) {
    log(
      `contract MathLib deployed at ${deployResult.address} using ${deployResult.receipt.gasUsed} gas`
    );
    await hre.run('verify:verify', {
      address: deployResult.address,
      constructorArguments: [],
    })
  }
};
module.exports.tags = ["MathLib"];
