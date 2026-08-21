const express = require("express");
const mongoose = require("mongoose");
const storage = require("../services/storage.service");

const router = express.Router();

// GET /api/files/:fileId — streams any stored file (photos, sketch, signatures).
router.get("/:fileId", async (req, res, next) => {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.fileId)) {
      return res.status(404).json({ error: "file not found" });
    }
    const metadata = await storage.getFileMetadata(req.params.fileId);
    if (!metadata) return res.status(404).json({ error: "file not found" });

    res.set("Content-Type", metadata.metadata?.contentType || "application/octet-stream");
    res.set("Content-Length", metadata.length);

    const downloadStream = storage.openDownloadStream(req.params.fileId);
    downloadStream.once("error", next);
    downloadStream.pipe(res);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
