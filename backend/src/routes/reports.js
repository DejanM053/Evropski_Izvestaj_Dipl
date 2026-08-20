const express = require("express");
const mongoose = require("mongoose");
const Report = require("../models/Report");

const router = express.Router();

// Note: only ?plate= is wired up. §5.1's Report schema has no deviceId
// field to scope by, so ?deviceId= is accepted but currently a no-op.
router.get("/", async (req, res, next) => {
  try {
    const { plate } = req.query;
    const filter = {};
    if (plate) {
      filter.$or = [{ "partyA.vehicle.plate": plate }, { "partyB.vehicle.plate": plate }];
    }
    const reports = await Report.find(filter).sort({ createdAt: -1 });
    res.json(reports);
  } catch (err) {
    next(err);
  }
});

router.get("/:id", async (req, res, next) => {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.id)) {
      return res.status(404).json({ error: "report not found" });
    }
    const report = await Report.findById(req.params.id);
    if (!report) return res.status(404).json({ error: "report not found" });
    res.json(report);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
