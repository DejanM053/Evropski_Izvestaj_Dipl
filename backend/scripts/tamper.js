#!/usr/bin/env node
/**
 * Demo helper for docs/master_plan.md §9's tamper step ("flip one byte of
 * the stored PDF, or swap a photo"). Mutates a report's stored bytes
 * directly in GridFS via storage.service.overwriteFile — nothing in the
 * Report document itself changes (pdf.sha256/attachmentHashes stay at
 * their original, honest values, exactly as if an attacker had reached
 * into the file store but not the database). A subsequent
 * `GET /api/reports/:id/verify` call recomputes the affected hash fresh
 * from GridFS, finds it no longer matches the on-chain record, and flips
 * the verdict to TAMPERED — naming the specific file in `attachments`
 * (photo mode) or `pdf.match` (default mode).
 *
 * Usage:
 *   node scripts/tamper.js <reportId>          # flip one byte of the PDF
 *   node scripts/tamper.js <reportId> --photo  # swap the first photo's bytes
 */
require("dotenv").config();
const mongoose = require("mongoose");
const config = require("../src/config");
const Report = require("../src/models/Report");
const storage = require("../src/services/storage.service");

// A different (but valid) 1x1 PNG from the ones used elsewhere in this repo's
// tests/fixtures, so a swapped photo is genuinely different bytes, not a
// no-op re-upload of the same content.
const REPLACEMENT_PHOTO_PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAAXNSR0IArs4c6QAAAAtJREFUCB1jYPgPAAEEAQB9tvNAAAAAAElFTkSuQmCC",
  "base64"
);

async function main() {
  const [, , reportId, flag] = process.argv;
  if (!reportId || !mongoose.Types.ObjectId.isValid(reportId)) {
    console.error("Usage: node scripts/tamper.js <reportId> [--photo]");
    process.exit(1);
  }

  await mongoose.connect(config.MONGO_URI);
  try {
    const report = await Report.findById(reportId);
    if (!report) {
      console.error(`No report found for id ${reportId}`);
      process.exitCode = 1;
      return;
    }

    if (flag === "--photo") {
      const photo = report.photos[0];
      if (!photo) {
        console.error("This report has no photos to swap.");
        process.exitCode = 1;
        return;
      }
      await storage.overwriteFile(photo.fileId, REPLACEMENT_PHOTO_PNG);
      console.log(`Swapped photo ${photo.fileId} for a different image.`);
      console.log("Report document untouched — only the GridFS bytes changed.");
    } else {
      if (!report.pdf?.fileId) {
        console.error("This report has no stored PDF yet (finalize it first).");
        process.exitCode = 1;
        return;
      }
      const buffer = await storage.getFileBuffer(report.pdf.fileId);
      buffer[0] ^= 0xff; // flip one byte
      await storage.overwriteFile(report.pdf.fileId, buffer);
      console.log(`Flipped one byte of the stored PDF ${report.pdf.fileId}.`);
      console.log("Report document untouched — only the GridFS bytes changed.");
    }

    console.log(`\nNow call GET /api/reports/${reportId}/verify — expect verdict: TAMPERED.`);
  } finally {
    await mongoose.disconnect();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
