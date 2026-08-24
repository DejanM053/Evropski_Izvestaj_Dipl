const mongoose = require("mongoose");
const Report = require("../models/Report");
const storage = require("./storage.service");
const { sha256, computeBundleHash } = require("./hash.service");
const chain = require("./chain.service");

class VerifyError extends Error {
  constructor(message, code = "VERIFY_ERROR") {
    super(message);
    this.name = "VerifyError";
    this.code = code;
  }
}

function normalizeHex(hex) {
  if (!hex) return null;
  return hex.toLowerCase().replace(/^0x/, "");
}

// Recomputes a file's sha256 straight from its current GridFS bytes — never
// the value already sitting in Mongo. Returns null (not a throw) for a
// missing/unreadable file, which the caller treats as a mismatch rather
// than a hard error: a report can legitimately have lost an attachment.
async function recomputeFileHash(fileId) {
  if (!fileId) return null;
  try {
    const buffer = await storage.getFileBuffer(fileId);
    return sha256(buffer);
  } catch (err) {
    return null;
  }
}

// §5.5 — the thesis centerpiece. Every hash here is recomputed from bytes
// actually read back from GridFS/chain right now; Mongo's own
// `pdf.sha256`/`attachmentHashes[].sha256` fields are surfaced only as
// `storedHash`, a third data point for the UI, never as an input to a
// match check. The authoritative comparison is always
// recomputed-just-now vs on-chain (immutable once anchored) — that's what
// still catches tampering even if an attacker edited both a file's bytes
// *and* its stored hash field in Mongo, which is the entire reason this
// app anchors on-chain instead of only trusting its own database.
async function verifyReport(reportId) {
  if (!mongoose.Types.ObjectId.isValid(reportId)) {
    throw new VerifyError("report not found", "REPORT_NOT_FOUND");
  }
  const report = await Report.findById(reportId);
  if (!report) {
    throw new VerifyError("report not found", "REPORT_NOT_FOUND");
  }

  // Steps 1-2: pull the PDF bytes back out of GridFS, recompute SHA-256.
  const pdfRecomputedHash = await recomputeFileHash(report.pdf?.fileId);

  // Step 4: recompute every attachment's hash from its current bytes, and
  // rebuild bundleHash the same deterministic way hash.service.js does at
  // finalize time (sorted recomputed hex strings, re-hashed) — using the
  // freshly recomputed values, not whatever is stored on the report. A
  // missing file recomputes to null, folded into the bundle input as ""
  // (guaranteed to make the bundle hash mismatch, which is the correct
  // outcome for a vanished attachment).
  const attachmentDetails = await Promise.all(
    (report.attachmentHashes || []).map(async (entry) => {
      const recomputedHash = await recomputeFileHash(entry.fileId);
      return {
        fileId: String(entry.fileId),
        kind: entry.kind,
        recomputedHash,
        match: recomputedHash !== null && recomputedHash === entry.sha256,
      };
    })
  );
  const bundleRecomputedHash = computeBundleHash(attachmentDetails.map((a) => a.recomputedHash || ""));
  const attachments = attachmentDetails.map(({ fileId, kind, match }) => ({ fileId, kind, match }));

  // Step 3: read the on-chain record. Only attempted once the report at
  // least claims to be anchored (`chain.txHash` set) — a report that was
  // never finalized has nothing on-chain to read, so there's no point
  // spending an RPC call to learn what's already known.
  const reportId32 = chain.deriveReportId32(report._id);
  const claimsAnchored = Boolean(report.chain?.txHash);
  const onChain = claimsAnchored ? await chain.getOnChainRecord(reportId32) : null;
  const anchored = claimsAnchored && onChain !== null;

  const onChainPdfHash = anchored ? normalizeHex(onChain.pdfHash) : null;
  const onChainBundleHash = anchored ? normalizeHex(onChain.bundleHash) : null;

  const pdfMatch = anchored && pdfRecomputedHash !== null && pdfRecomputedHash === onChainPdfHash;
  const bundleMatch = anchored && bundleRecomputedHash !== null && bundleRecomputedHash === onChainBundleHash;

  const verdict = !anchored ? "NOT_ANCHORED" : pdfMatch && bundleMatch ? "VERIFIED" : "TAMPERED";

  return {
    reportId: String(report._id),
    pdf: {
      storedHash: report.pdf?.sha256 || null,
      recomputedHash: pdfRecomputedHash,
      onChainHash: onChainPdfHash,
      match: pdfMatch,
    },
    bundle: {
      recomputedHash: bundleRecomputedHash,
      onChainHash: onChainBundleHash,
      match: bundleMatch,
    },
    attachments,
    chain: {
      txHash: report.chain?.txHash || null,
      blockNumber: report.chain?.blockNumber ?? null,
      network: report.chain?.network || null,
      anchoredAt: report.chain?.anchoredAt || null,
    },
    verdict,
  };
}

module.exports = { verifyReport, VerifyError };
