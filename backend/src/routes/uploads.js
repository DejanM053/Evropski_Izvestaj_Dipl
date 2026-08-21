const express = require("express");
const multer = require("multer");
const { requireUnsealedReport } = require("../services/report-guard.service");
const storage = require("../services/storage.service");
const { sha256 } = require("../services/hash.service");

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

      res.status(201).json({ fileId, sha256: hash, caption: caption || "", party, takenAt });
    } catch (err) {
      next(err);
    }
  }
);

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

      res.status(201).json({ fileId, sha256: hash, party, signedAt });
    } catch (err) {
      next(err);
    }
  }
);

module.exports = router;
