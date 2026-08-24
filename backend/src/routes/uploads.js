const express = require("express");
const multer = require("multer");
const mongoose = require("mongoose");
const Session = require("../models/Session");
const { requireUnsealedReport } = require("../services/report-guard.service");
const storage = require("../services/storage.service");
const { sha256 } = require("../services/hash.service");
const { maybeLockReport } = require("../services/report-lock.service");

const router = express.Router();

const ALLOWED_MIME_TYPES = ["image/png", "image/jpeg"];
const MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024;

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_FILE_SIZE_BYTES },
  fileFilter: (req, file, cb) => {
    if (ALLOWED_MIME_TYPES.includes(file.mimetype)) return cb(null, true);
    const err = new Error(`unsupported file type "${file.mimetype}"; only PNG/JPEG allowed`);
    err.code = "UNSUPPORTED_MEDIA_TYPE";
    cb(err);
  },
});

// Wraps multer's callback-style middleware so fileFilter/size errors are
// turned into proper 4xx responses here, instead of falling through to the
// app's generic 500 handler in app.js.
function uploadSingle(fieldName) {
  const middleware = upload.single(fieldName);
  return (req, res, next) => {
    middleware(req, res, (err) => {
      if (!err) return next();
      if (err.code === "UNSUPPORTED_MEDIA_TYPE") {
        return res.status(415).json({ error: err.message, code: err.code });
      }
      if (err instanceof multer.MulterError && err.code === "LIMIT_FILE_SIZE") {
        return res
          .status(413)
          .json({ error: `file exceeds ${MAX_FILE_SIZE_BYTES} byte limit`, code: err.code });
      }
      next(err);
    });
  };
}

function requireFile(req, res, next) {
  if (!req.file) return res.status(400).json({ error: "file is required" });
  next();
}

// Broadcasts a `report:patched`-shaped event (§5.3) from a REST route,
// reusing the exact {path, value, by} contract clients already handle for
// socket-originated patches — no new event type needed. `photos` can't go
// through the *client*-initiated report:patch path (classifyPatchPath in
// session.socket.js rejects it: a client-supplied whole-array replace would
// be unsafe last-write-wins for an additive list), but that restriction is
// about validating untrusted client input, not about what the server itself
// may broadcast after its own atomic, already-persisted mutation. Used to
// close the "photos aren't live-synced" gap (PROGRESS.md Known issues) and
// to sync a just-uploaded signature, both needed so the Review screen
// (Phase 8) shows the true both-sides state without requiring a reconnect.
function broadcastPatch(req, report, path, value, by) {
  const io = req.app.get("io");
  if (!io || !report.sessionId) return;
  io.to(String(report.sessionId)).emit("report:patched", { path, value, by });
}

// Removes the attachmentHashes entry for a file being replaced (sketch and
// signature are single-slot per report/party, unlike photos which are
// additive), and best-effort deletes the now-orphaned GridFS blob.
async function replaceAttachment(report, previousFileId) {
  if (!previousFileId) return;
  report.attachmentHashes = report.attachmentHashes.filter(
    (a) => !a.fileId || !a.fileId.equals(previousFileId)
  );
  try {
    await storage.deleteFile(previousFileId);
  } catch (err) {
    console.error(`failed to delete orphaned file ${previousFileId}: ${err.message}`);
  }
}

// POST /api/reports/:id/photos — multipart, additive (many photos per report).
router.post(
  "/:id/photos",
  requireUnsealedReport,
  uploadSingle("file"),
  requireFile,
  async (req, res, next) => {
    try {
      const { party, caption } = req.body;
      if (party !== "A" && party !== "B") {
        return res.status(400).json({ error: 'party must be "A" or "B"' });
      }

      const report = req.report;
      const hash = sha256(req.file.buffer);
      const fileId = await storage.storeBuffer(req.file.buffer, req.file.originalname, {
        contentType: req.file.mimetype,
        reportId: report._id,
      });

      const takenAt = new Date();
      report.photos.push({ fileId, caption: caption || "", party, takenAt });
      report.attachmentHashes.push({ fileId, sha256: hash, kind: "photo" });
      await report.save();

      broadcastPatch(req, report, "photos", report.toObject().photos, party);

      res.status(201).json({ fileId, sha256: hash, caption: caption || "", party, takenAt });
    } catch (err) {
      next(err);
    }
  }
);

// DELETE /api/reports/:id/photos/:fileId — removes one photo before the
// report is sealed (docs/master_plan.md §6 screen 9: "delete before lock").
// Not in the original §5.2 endpoint list — added in Phase 7 once the mobile
// Photos screen needed it; mirrors replaceAttachment's
// attachmentHashes-filter + best-effort GridFS delete.
router.delete("/:id/photos/:fileId", requireUnsealedReport, async (req, res, next) => {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.fileId)) {
      return res.status(404).json({ error: "photo not found" });
    }
    const fileId = new mongoose.Types.ObjectId(req.params.fileId);
    const report = req.report;
    const exists = report.photos.some((p) => p.fileId && p.fileId.equals(fileId));
    if (!exists) return res.status(404).json({ error: "photo not found" });

    report.photos = report.photos.filter((p) => !p.fileId || !p.fileId.equals(fileId));
    await replaceAttachment(report, fileId);
    await report.save();

    broadcastPatch(req, report, "photos", report.toObject().photos, "system");

    res.status(204).end();
  } catch (err) {
    next(err);
  }
});

// POST /api/reports/:id/sketch — single PNG, shared between both parties.
router.post(
  "/:id/sketch",
  requireUnsealedReport,
  uploadSingle("file"),
  requireFile,
  async (req, res, next) => {
    try {
      const report = req.report;
      const hash = sha256(req.file.buffer);
      const previousFileId = report.sketch.fileId;

      const fileId = await storage.storeBuffer(req.file.buffer, req.file.originalname, {
        contentType: req.file.mimetype,
        reportId: report._id,
      });

      await replaceAttachment(report, previousFileId);
      report.sketch.fileId = fileId;
      report.attachmentHashes.push({ fileId, sha256: hash, kind: "sketch" });
      await report.save();

      res.status(201).json({ fileId, sha256: hash });
    } catch (err) {
      next(err);
    }
  }
);

// POST /api/reports/:id/signature — single PNG per party.
router.post(
  "/:id/signature",
  requireUnsealedReport,
  uploadSingle("file"),
  requireFile,
  async (req, res, next) => {
    try {
      const { party } = req.body;
      if (party !== "A" && party !== "B") {
        return res.status(400).json({ error: 'party must be "A" or "B"' });
      }

      const report = req.report;
      const partyKey = party === "A" ? "partyA" : "partyB";
      const hash = sha256(req.file.buffer);
      const previousFileId = report[partyKey].signature.fileId;

      const fileId = await storage.storeBuffer(req.file.buffer, req.file.originalname, {
        contentType: req.file.mimetype,
        reportId: report._id,
      });

      await replaceAttachment(report, previousFileId);
      const signedAt = new Date();
      report[partyKey].signature.fileId = fileId;
      report[partyKey].signature.signedAt = signedAt;
      report.attachmentHashes.push({ fileId, sha256: hash, kind: "signature" });
      await report.save();

      broadcastPatch(req, report, `${partyKey}.signature`, { fileId: fileId.toString(), signedAt }, party);

      // Phase 8: a signature is the other half (alongside confirmedReview,
      // patched via the generic report:patch mechanism) of the "lock"
      // condition — check it here too, since this REST route is a write
      // path maybeLockReport's caller in session.socket.js never sees.
      const session = report.sessionId ? await Session.findById(report.sessionId) : null;
      await maybeLockReport(report, session, req.app.get("io"));

      res.status(201).json({ fileId, sha256: hash, party, signedAt });
    } catch (err) {
      next(err);
    }
  }
);

module.exports = router;
