const { LOCKED_STATUSES } = require("../models/statuses");

// One party's own half of the "signed off" condition — confirmed review
// *and* a stored signature. Used both to compute bothPartiesSignedOff
// below and, since this phase, to freeze a party's own subtree the
// instant *they* sign rather than waiting for the other party too (see
// session.socket.js's report:patch handler and uploads.js's signature
// route) — narrowing the window between "what a party signed off on" and
// "what actually ends up in the finalized report" without needing both
// parties to be done.
function partySignedOff(report, party) {
  const partyKey = party === "A" ? "partyA" : "partyB";
  return Boolean(report[partyKey].confirmedReview && report[partyKey].signature.fileId);
}

function bothPartiesSignedOff(report) {
  return partySignedOff(report, "A") && partySignedOff(report, "B");
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

module.exports = { maybeLockReport, bothPartiesSignedOff, partySignedOff };
