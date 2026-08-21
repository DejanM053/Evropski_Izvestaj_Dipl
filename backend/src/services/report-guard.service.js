const mongoose = require("mongoose");
const Report = require("../models/Report");

class SealedReportError extends Error {
  constructor(reportId) {
    super(`report ${reportId} is sealed and immutable`);
    this.name = "SealedReportError";
    this.code = "REPORT_SEALED";
  }
}

function assertReportNotSealed(report) {
  if (report.status === "sealed") {
    throw new SealedReportError(report._id);
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
    if (err instanceof SealedReportError) {
      return res.status(409).json({ error: err.message, code: err.code });
    }
    next(err);
  }
}

module.exports = { assertReportNotSealed, requireUnsealedReport, SealedReportError };
