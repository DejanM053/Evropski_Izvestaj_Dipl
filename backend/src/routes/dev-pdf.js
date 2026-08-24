const express = require("express");
const mongoose = require("mongoose");
const Report = require("../models/Report");
const { generateReportPdf } = require("../services/pdf.service");

const router = express.Router();

// TEMPORARY — Phase 9 only. Lets the PDF layout be iterated on by hitting a
// URL, instead of re-running a full two-device session through to signing
// every time. Not in docs/master_plan.md §5.2's endpoint list — the real
// production PDF route, `GET /api/reports/:id/pdf`, streams the *stored*
// PDF from GridFS after finalize (Phase 10) and doesn't exist yet. This one
// always regenerates from whatever state the report is in right now
// (sealed or not — no `requireUnsealedReport` guard, since a read-only
// preview has no reason to reject a sealed report). Delete this file and
// its one `app.use` in app.js once Phase 10 makes it redundant.

// GET /api/dev/reports — a report id is required to hit the route below;
// this lists the newest ones (id, plates, status) so there's no need to
// open mongosh just to find one to test against.
router.get("/reports", async (req, res, next) => {
  try {
    const reports = await Report.find(
      {},
      "_id createdAt status partyA.vehicle.plate partyB.vehicle.plate"
    )
      .sort({ createdAt: -1 })
      .limit(50);

    res.json(
      reports.map((r) => ({
        _id: r._id,
        createdAt: r.createdAt,
        status: r.status,
        partyAPlate: r.partyA?.vehicle?.plate || null,
        partyBPlate: r.partyB?.vehicle?.plate || null,
      }))
    );
  } catch (err) {
    next(err);
  }
});

// GET /api/dev/reports/:id/pdf — regenerate and stream inline.
router.get("/reports/:id/pdf", async (req, res, next) => {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.id)) {
      return res.status(404).json({ error: "report not found" });
    }
    const report = await Report.findById(req.params.id);
    if (!report) return res.status(404).json({ error: "report not found" });

    const buffer = await generateReportPdf(report);
    res.set("Content-Type", "application/pdf");
    res.set("Content-Disposition", `inline; filename="report-${report._id}-preview.pdf"`);
    res.send(buffer);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
