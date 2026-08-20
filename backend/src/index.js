const mongoose = require("mongoose");
const config = require("./config");
const { createApp } = require("./app");

async function connectMongoWithRetry(uri, retryDelayMs = 3000) {
  for (;;) {
    try {
      await mongoose.connect(uri);
      console.log("mongo connected");
      return;
    } catch (err) {
      console.error(`mongo connection failed (${err.message}), retrying in ${retryDelayMs}ms`);
      await new Promise((resolve) => setTimeout(resolve, retryDelayMs));
    }
  }
}

const { server } = createApp();

connectMongoWithRetry(config.MONGO_URI);

server.listen(config.PORT, () => {
  console.log(`backend listening on port ${config.PORT}`);
});
