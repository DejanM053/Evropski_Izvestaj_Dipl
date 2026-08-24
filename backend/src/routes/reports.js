const express = require("express");
const mongoose = require("mongoose");
const Report = require("../models/Report");
const storage = require("../services/storage.service");
const { runFinalize, FinalizeError } = require("../services/finalize.service");

const router = express.Router();

const FINALIZE_ERROR_STATUS = {
  NOT_READY: 409,
  INVALID_STATUS: 409,
  ANCHOR_FAILED: 502,
  REPORT_NOT_FOUND: 404,
};

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

// GET /api/reports/:id/pdf — streams the *stored* PDF from GridFS. Only
// meaningful once finalize (§5.4) has run at least far enough to store one
// (report.pdf.fileId set); until then there's nothing to stream. This is
// the real route the temporary dev-only preview route (routes/dev-pdf.js,
// Phase 9) was always meant to be replaced by — see PROGRESS.md.
router.get("/:id/pdf", async (req, res, next) => {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.id)) {
      return res.status(404).json({ error: "report not found" });
    }
    const report = await Report.findById(req.params.id, "pdf");
    if (!report || !report.pdf?.fileId) {
      return res.status(404).json({ error: "PDF not available for this report yet" });
    }

    res.set("Content-Type", "application/pdf");
    res.set("Content-Disposition", `inline; filename="report-${report._id}.pdf"`);

    const downloadStream = storage.openDownloadStream(report.pdf.fileId);
    downloadStream.once("error", next);
    downloadStream.pipe(res);
  } catch (err) {
    next(err);
  }
});

// POST /api/reports/:id/finalize — §5.4's ordered pipeline, run/resumed by
// finalize.service.js. No requireUnsealedReport here: that guard rejects
// every LOCKED_STATUSES value including "signing" and "finalizing", which
// are exactly the two statuses this route must accept (a fresh finalize and
// an anchor-only retry, respectively) — see finalize.service.js's own
// status handling for the rest of the state machine.
router.post("/:id/finalize", async (req, res, next) => {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.id)) {
      return res.status(404).json({ error: "report not found" });
    }
    const io = req.app.get("io");
    const result = await runFinalize(req.params.id, io);
    res.status(200).json(result.report);
  } catch (err) {
    if (err instanceof FinalizeError) {
      if (err.code === "FINALIZE_IN_PROGRESS") {
        // Not an error from the caller's point of view — another request
        // (this party's own retry, or the other party's client) already
        // owns the pipeline run. The caller should fall back to listening
        // for report:progress/report:sealed rather than treating this as a
        // failure.
        return res.status(202).json({ status: "finalizing", message: err.message });
      }
      const statusCode = FINALIZE_ERROR_STATUS[err.code] || 500;
      return res.status(statusCode).json({ error: err.message, code: err.code });
    }
    next(err);
  }
});

module.exports = router;
