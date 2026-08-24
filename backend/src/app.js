const http = require("http");
const express = require("express");
const cors = require("cors");
const { Server } = require("socket.io");
const healthRouter = require("./routes/health");
const sessionsRouter = require("./routes/sessions");
const reportsRouter = require("./routes/reports");
const uploadsRouter = require("./routes/uploads");
const filesRouter = require("./routes/files");
const registerSessionHandlers = require("./sockets/session.socket");

function createApp() {
  const app = express();
  // Only the mobile app talks to this REST API in normal use (Socket.IO
  // already allows any origin above), but `flutter run -d chrome` serves
  // the app from its own localhost origin, which the browser would
  // otherwise block from calling :3000. No auth/cookies are involved
  // anywhere in this API, so an open origin carries no meaningful risk.
  app.use(cors());
  app.use(express.json());
  app.use("/api", healthRouter);
  app.use("/api/sessions", sessionsRouter);
  app.use("/api/reports", reportsRouter);
  app.use("/api/reports", uploadsRouter);
  app.use("/api/files", filesRouter);

  app.use((err, req, res, next) => {
    console.error(err);
    res.status(500).json({ error: "internal server error" });
  });

  const server = http.createServer(app);
  const io = new Server(server, { cors: { origin: "*" } });
  registerSessionHandlers(io);

  return { app, server, io };
}

module.exports = { createApp };
