module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, log } = deployments;
  const namedAccounts = await getNamedAccounts();
  const { admin } = namedAccounts;

  const baseToken = await deployments.get("BaseToken");
  const quoteToken = await deployments.get("QuoteToken");
  const mathLib = await deployments.get("MathLib");
  const name = "EGT LP Token";
  const symbol = "EGTLPS";
  const deployResult = await deploy("EGT Exchange", {
    from: admin,
    contract: "Exchange",
    args: [name, symbol, quoteToken.address, baseToken.address],
    libraries: {
      MathLib: mathLib.address,
    },
  });
  if (deployResult.newlyDeployed) {
    log(
      `contract EGT Exchange deployed at ${deployResult.address} using ${deployResult.receipt.gasUsed} gas`
    );
  }
};
module.exports.tags = ["EGT Exchange"];
module.exports.dependencies = ["QuoteToken", "BaseToken", "MathLib"];
