const Session = require("../models/Session");
const Report = require("../models/Report");
const { LOCKED_STATUSES } = require("../models/statuses");
const {
  assertReportNotSealed,
  SealedReportError,
  ReportLockedError,
} = require("../services/report-guard.service");
const { maybeLockReport } = require("../services/report-lock.service");

function emitError(socket, code, message) {
  socket.emit("session:error", { code, message });
}

// partyA.*/partyB.* are owned by their party; accident.*/sketch(.*) are
// shared, last-write-wins. Anything else (status, chain, pdf, ...) is
// server-controlled and not patchable through this generic mechanism.
function classifyPatchPath(path) {
  if (path === "sketch" || path.startsWith("sketch.")) return { scope: "shared" };
  if (path === "accident" || path.startsWith("accident.")) return { scope: "shared" };
  if (path === "partyA" || path.startsWith("partyA.")) return { scope: "party", party: "A" };
  if (path === "partyB" || path.startsWith("partyB.")) return { scope: "party", party: "B" };
  return null;
}

function registerSessionHandlers(io) {
  io.on("connection", (socket) => {
    socket.on("session:join", async ({ sessionId, party } = {}) => {
      try {
        if (party !== "A" && party !== "B") {
          return emitError(socket, "INVALID_PARTY", 'party must be "A" or "B"');
        }
        const session = await Session.findById(sessionId).catch(() => null);
        if (!session) return emitError(socket, "SESSION_NOT_FOUND", "session not found");

        const partyKey = party === "A" ? "partyA" : "partyB";
        session[partyKey].socketId = socket.id;
        if (!session[partyKey].joinedAt) session[partyKey].joinedAt = new Date();
        await session.save();

        socket.join(sessionId);
        socket.data.sessionId = sessionId;
        socket.data.party = party;

        const report = session.reportId ? await Report.findById(session.reportId) : null;
        socket.emit("session:state", {
          session: session.toObject(),
          report: report ? report.toObject() : null,
        });

        io.to(sessionId).emit("party:status", {
          party,
          stage: null,
          ready: session[partyKey].ready,
        });
      } catch (err) {
        emitError(socket, "INTERNAL_ERROR", "failed to join session");
      }
    });

    socket.on("report:patch", async ({ path, value } = {}) => {
      try {
        const { sessionId, party } = socket.data;
        if (!sessionId || !party) {
          return emitError(socket, "NOT_JOINED", "join the session before patching");
        }
        if (typeof path !== "string" || path.length === 0) {
          return emitError(socket, "INVALID_PATCH", "path is required");
        }
        const classification = classifyPatchPath(path);
        if (!classification) {
          return emitError(socket, "INVALID_PATCH", `path "${path}" is not patchable`);
        }
        if (classification.scope === "party" && classification.party !== party) {
          return emitError(socket, "FORBIDDEN_PATCH", "cannot patch another party's subtree");
        }

        const session = await Session.findById(sessionId);
        if (!session) return emitError(socket, "SESSION_NOT_FOUND", "session not found");
        if (LOCKED_STATUSES.includes(session.status)) {
          return emitError(socket, "SESSION_LOCKED", `cannot patch while status is "${session.status}"`);
        }

        const report = await Report.findById(session.reportId);
        if (!report) return emitError(socket, "REPORT_NOT_FOUND", "report not found");
        assertReportNotSealed(report);

        report.set(path, value);
        await report.save();

        io.to(sessionId).emit("report:patched", { path, value, by: party });

        // Cheap idempotent check (Phase 8): a patch into partyA/partyB can be
        // the one that completes "both confirmed review + both signed" (e.g.
        // Review screen's confirmedReview patch), so re-check after every
        // accepted patch rather than trying to filter to just that path.
        await maybeLockReport(report, session, io);
      } catch (err) {
        if (err instanceof SealedReportError || err instanceof ReportLockedError) {
          return emitError(socket, err.code, err.message);
        }
        emitError(socket, "INVALID_PATCH", err.message || "failed to apply patch");
      }
    });

    socket.on("party:ready", async ({ party, stage } = {}) => {
      try {
        const { sessionId, party: socketParty } = socket.data;
        if (!sessionId || !socketParty) {
          return emitError(socket, "NOT_JOINED", "join the session before signaling ready");
        }
        if (party !== socketParty) {
          return emitError(socket, "FORBIDDEN_PATCH", "cannot signal ready for another party");
        }

        const session = await Session.findById(sessionId);
        if (!session) return emitError(socket, "SESSION_NOT_FOUND", "session not found");

        const partyKey = party === "A" ? "partyA" : "partyB";
        session[partyKey].ready = true;
        await session.save();

        io.to(sessionId).emit("party:status", { party, stage, ready: true });
      } catch (err) {
        emitError(socket, "INTERNAL_ERROR", "failed to update ready state");
      }
    });
  });
}

module.exports = registerSessionHandlers;
