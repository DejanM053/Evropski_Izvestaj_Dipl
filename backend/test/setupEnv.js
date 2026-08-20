process.env.MONGO_URI = process.env.MONGO_URI || "mongodb://localhost:27017/accident-report-test";
process.env.RPC_URL = process.env.RPC_URL || "http://localhost:8545";
process.env.CONTRACT_ADDRESS =
  process.env.CONTRACT_ADDRESS || "0x0000000000000000000000000000000000000000";
process.env.PRIVATE_KEY =
  process.env.PRIVATE_KEY ||
  "0x0000000000000000000000000000000000000000000000000000000000000000";
process.env.CHAIN_NETWORK = process.env.CHAIN_NETWORK || "test";
process.env.PORT = process.env.PORT || "0";
