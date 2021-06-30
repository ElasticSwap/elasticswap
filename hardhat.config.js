require("@nomiclabs/hardhat-waffle");
require("hardhat-contract-sizer");
require("hardhat-deploy");

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.8.4",
  settings: {
    optimizer: {
      enabled: true,
    },
  },
  networks: {
    hardhat: {
      deploy: ["deploy/core", "deploy/test"],
    },
  },
  paths: {
    deploy: ["deploy/core"],
    sources: "./src",
  },
  namedAccounts: {
    admin: {
      default: 0,
    },
    liquidityProvider1: {
      default: 1,
    },
    liquidityProvider2: {
      default: 2,
    },
    trader1: {
      default: 3,
    },
    trader2: {
      default: 4,
    },
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
  },
};
