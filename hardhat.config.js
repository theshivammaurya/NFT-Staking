require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("@openzeppelin/hardhat-upgrades");
require('dotenv').config();
const { ethers, JsonRpcProvider } = require("ethers");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.24",
  networks:{
    taral: {
      chainId: 4440,
      url: "https://devnet-taral-rpc1.tarality.com",
      accounts: ["fbc28b4dfb62b28ab3fbd1272f7b00450cb3a08261dbdc70f54329c409be3935"],
    },
    },
  }
  


  // Explorer URL -    https://devnet.taralscan.com/