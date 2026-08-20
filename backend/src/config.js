require("dotenv").config();

const REQUIRED_VARS = [
  "MONGO_URI",
  "RPC_URL",
  "CONTRACT_ADDRESS",
  "PRIVATE_KEY",
  "CHAIN_NETWORK",
  "PORT",
];

const missing = REQUIRED_VARS.filter((key) => !process.env[key]);
if (missing.length > 0) {
  console.error(
    `Missing required environment variable(s): ${missing.join(", ")}. ` +
      "Copy .env.example to .env and fill them in."
  );
  process.exit(1);
}

module.exports = {
  MONGO_URI: process.env.MONGO_URI,
  RPC_URL: process.env.RPC_URL,
  CONTRACT_ADDRESS: process.env.CONTRACT_ADDRESS,
  PRIVATE_KEY: process.env.PRIVATE_KEY,
  CHAIN_NETWORK: process.env.CHAIN_NETWORK,
  PORT: parseInt(process.env.PORT, 10),
};
