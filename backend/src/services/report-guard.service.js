const mongoose = require("mongoose");
const Report = require("../models/Report");
const { LOCKED_STATUSES } = require("../models/statuses");

class SealedReportError extends Error {
  constructor(reportId) {
    super(`report ${reportId} is sealed and immutable`);
    this.name = "SealedReportError";
    this.code = "REPORT_SEALED";
  }
}

// Phase 8: once both signatures are in, Report.status (and Session.status,
// kept in sync from that moment on — see report-lock.service.js) moves to
// "signing" ahead of "sealed". Same "reject the write" behavior, distinct
// error/code so callers can tell "temporarily locked, signing/finalizing in
// flight" apart from "permanently sealed" — REPORT_SEALED stays reserved
// for the literal status === "sealed" case, exactly as before this phase.
class ReportLockedError extends Error {
  constructor(report) {
    super(`report ${report._id} is locked (status "${report.status}") and cannot be modified`);
    this.name = "ReportLockedError";
    this.code = "REPORT_LOCKED";
  }
}

function assertReportNotSealed(report) {
  if (report.status === "sealed") {
    throw new SealedReportError(report._id);
  }
  if (LOCKED_STATUSES.includes(report.status)) {
    throw new ReportLockedError(report);
  }
}

// Express middleware for future mutating routes (photos, sketch, signature,
// finalize). Loads the report onto req.report so handlers don't refetch it.
async function requireUnsealedReport(req, res, next) {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.id)) {
      return res.status(404).json({ error: "report not found" });
    }
    const report = await Report.findById(req.params.id);
    if (!report) return res.status(404).json({ error: "report not found" });
    assertReportNotSealed(report);
    req.report = report;
    next();
  } catch (err) {
    if (err instanceof SealedReportError || err instanceof ReportLockedError) {
      return res.status(409).json({ error: err.message, code: err.code });
    }
    next(err);
  }
}

module.exports = {
  assertReportNotSealed,
  requireUnsealedReport,
  SealedReportError,
  ReportLockedError,
};
