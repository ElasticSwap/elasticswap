require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require("hardhat-contract-sizer");
require("hardhat-gas-reporter");
require("hardhat-deploy");
require("solidity-coverage");
require("dotenv").config();

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    version: "0.8.4",
    settings: {
      optimizer: {
        enabled: true,
        runs: 100000,
      },
    },
  },
  networks: {
    hardhat: {
      deploy: ["deploy/core", "deploy/test", "deploy/testnet"],
    },
    goerli: {
      deploy: ["deploy/core", "deploy/testnet"],
      url: process.env.GOERLI_URL,
      accounts:
        process.env.GOERLI_PRIVATE_KEY !== undefined
          ? [process.env.GOERLI_PRIVATE_KEY]
          : [],
    },
    fuji: {
      deploy: ["deploy/core", "deploy/testnet"],
      url: "https://api.avax-test.network/ext/bc/C/rpc",
      gasPrice: 225000000000,
      chainId: 43113,
      accounts:
        process.env.FUJI_PRIVATE_KEY !== undefined
          ? [process.env.FUJI_PRIVATE_KEY]
          : [],
    },
    avalanche: {
      deploy: ["deploy/core"],
      url: "https://api.avax.network/ext/bc/C/rpc",
      gasPrice: 50000000000, // 58 nAVAX (10e9)
      chainId: 43114,
      accounts:
        process.env.AVAX_PRIVATE_KEY !== undefined
          ? [process.env.AVAX_PRIVATE_KEY]
          : [],
    },
  },
  etherscan: {
    // Your API key for Snowtrace
    // Obtain one at https://snowtrace.io/
    apiKey: process.env.ETHERSCAN_API_KEY,
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
    feeRecipient: {
      default: 5,
      goerli: process.env.GOERLI_FEE_ADDRESS,
      fuji: process.env.FUJI_FEE_ADDRESS,
      avalanche: process.env.AVAX_FEE_ADDRESS,
    },
    DAO: {
      default: 9,
      goerli: process.env.GOERLI_DAO_ADDRESS,
      fuji: process.env.FUJI_DAO_ADDRESS,
      avalanche: process.env.AVAX_DAO_ADDRESS,
    },
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
  },
  gasReporter: {
    enabled: true,
    currency: "USD",
  },
};
