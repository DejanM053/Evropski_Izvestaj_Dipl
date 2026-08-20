const express = require("express");
const mongoose = require("mongoose");
const config = require("../config");
const chain = require("../services/chain.service");

const router = express.Router();

router.get("/health", async (req, res) => {
  const result = {
    mongo: mongoose.connection.readyState === 1 ? "ok" : "error: not connected",
    chain: "ok",
    contract: config.CONTRACT_ADDRESS,
    network: config.CHAIN_NETWORK,
  };

  try {
    await chain.checkChain();
  } catch (err) {
    result.chain = `error: ${err.message}`;
  }

  const ok = result.mongo === "ok" && result.chain === "ok";
  res.status(ok ? 200 : 503).json(result);
});

module.exports = router;
