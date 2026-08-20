const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");
const config = require("../config");

const { abi } = JSON.parse(
  fs.readFileSync(path.join(__dirname, "..", "abi", "AccidentRegistry.json"), "utf8")
);

const provider = new ethers.JsonRpcProvider(config.RPC_URL);
const contract = new ethers.Contract(config.CONTRACT_ADDRESS, abi, provider);

// Cheap read-only call that never reverts, used to prove the RPC connection
// and the deployed contract are both reachable.
async function checkChain() {
  await contract.verify(ethers.ZeroHash, ethers.ZeroHash);
}

module.exports = { provider, contract, checkChain };
