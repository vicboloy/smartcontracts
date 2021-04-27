// require("@nomiclabs/hardhat-waffle")
require("hardhat-gas-reporter")
require("solidity-coverage");
require("@nomiclabs/hardhat-truffle5");

task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.6.6"
      },
      {
        version: "0.5.16"
      },
      {
        version: "0.4.18"
      },
      {
        version: "0.4.17"
      }
    ]
  },
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {},
    ganache: {
      url: "http://127.0.0.1:7545",
      accounts: {
        mnemonic: "license jewel era decade still have castle foil diesel scrub mutual floor"
      }
    },
    ropsten: {
      url: "https://ropsten.infura.io/v3/e2b3170345084948b85a3cd29d849495",
      gas: 5500000,
      gasMultiplier: 3,
      accounts: {
        mnemonic: "guess delay book adjust unfair settle income east february festival obvious sting"
      }
    },
    main: {
      url: "https://mainnet.infura.io/v3/6e12ffaa544047658f0185873ddcbd89"
    }
  },
  gasReporter: {
    currency: 'USD',
    coinmarketcap: '99f32a19-565a-444a-8238-e89dc9a0d7c3'
  }
};
