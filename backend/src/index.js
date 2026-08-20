const http = require("http");
const express = require("express");
const { Server } = require("socket.io");
const mongoose = require("mongoose");
const config = require("./config");
const healthRouter = require("./routes/health");

const app = express();
app.use(express.json());
app.use("/api", healthRouter);

const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });

io.on("connection", (socket) => {
  console.log(`socket connected: ${socket.id}`);
});

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

connectMongoWithRetry(config.MONGO_URI);

server.listen(config.PORT, () => {
  console.log(`backend listening on port ${config.PORT}`);
});
