const { LOCKED_STATUSES } = require("../models/statuses");

function bothPartiesSignedOff(report) {
  return Boolean(
    report.partyA.confirmedReview &&
      report.partyB.confirmedReview &&
      report.partyA.signature.fileId &&
      report.partyB.signature.fileId
  );
}

// §5.4 step 1 / Phase 8: once both parties have confirmed review and
// uploaded a signature, the report moves to "signing" — locked against
// further edits, awaiting finalize (Phase 10). Bumps Report.status and
// Session.status together (they'd been allowed to drift apart until now —
// see the "Known scope gaps" note in .claude/rules/backend.md) so the
// socket guard (session.status, checked in session.socket.js) and the REST
// guard (report.status, report-guard.service.js) both start rejecting
// writes from the same moment. Idempotent and safe to call after every
// accepted patch/upload: a report already at or past "signing" is left
// alone, so callers don't need to track whether *this* particular write
// was the one that completed the pair.
async function maybeLockReport(report, session, io) {
  if (LOCKED_STATUSES.includes(report.status)) return false;
  if (!bothPartiesSignedOff(report)) return false;

  report.status = "signing";
  await report.save();

  if (session && session.status !== "signing") {
    session.status = "signing";
    await session.save();
  }

  if (io && session) {
    io.to(String(session._id)).emit("report:locked");
  }

  return true;
}

module.exports = { maybeLockReport, bothPartiesSignedOff };
