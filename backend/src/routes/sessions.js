const express = require("express");
const mongoose = require("mongoose");
const Session = require("../models/Session");
const Report = require("../models/Report");
const { generateUniqueSessionCode } = require("../services/session-code.service");

const router = express.Router();
const SESSION_TTL_MS = 24 * 60 * 60 * 1000;

router.post("/", async (req, res, next) => {
  try {
    const sessionCode = await generateUniqueSessionCode();
    const report = await Report.create({});
    const session = await Session.create({
      sessionCode,
      reportId: report._id,
      expiresAt: new Date(Date.now() + SESSION_TTL_MS),
    });
    report.sessionId = session._id;
    await report.save();

    res.status(201).json({
      sessionId: session._id,
      sessionCode: session.sessionCode,
      reportId: report._id,
    });
  } catch (err) {
    next(err);
  }
});

router.post("/:code/join", async (req, res, next) => {
  try {
    const code = req.params.code.toUpperCase();
    const session = await Session.findOne({
      sessionCode: code,
      expiresAt: { $gt: new Date() },
    });
    if (!session) return res.status(404).json({ error: "session not found" });
    if (session.status !== "waiting") {
      return res.status(409).json({ error: "session already has both parties" });
    }

    session.status = "joined";
    await session.save();

    res.json({
      sessionId: session._id,
      sessionCode: session.sessionCode,
      reportId: session.reportId,
    });
  } catch (err) {
    next(err);
  }
});

router.get("/:id", async (req, res, next) => {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.id)) {
      return res.status(404).json({ error: "session not found" });
    }
    const session = await Session.findById(req.params.id);
    if (!session) return res.status(404).json({ error: "session not found" });
    const report = session.reportId ? await Report.findById(session.reportId) : null;

    res.json({ session, report });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
