const Report = require("../models/Report");
const Session = require("../models/Session");
const config = require("../config");
const storage = require("./storage.service");
const { sha256, computeBundleHash } = require("./hash.service");
const { generateReportPdf } = require("./pdf.service");
const chain = require("./chain.service");
const { bothPartiesSignedOff } = require("./report-lock.service");

class FinalizeError extends Error {
  constructor(message, code = "FINALIZE_ERROR") {
    super(message);
    this.name = "FinalizeError";
    this.code = code;
  }
}

// Per-report in-flight guard. This is a single Node process (no clustering
// per docker-compose §7), so a plain in-memory Set fully serializes calls
// for the same report — both parties' clients can hit POST /finalize around
// the same moment (one auto-triggers on reaching screen 12, the other may
// too on reconnect), and this makes the loser a cheap no-op instead of a
// second concurrent pipeline run (double PDF generation, or worse, two
// concurrent anchor() sends racing for the same nonce).
const _inFlight = new Set();

function emitProgress(io, sessionId, step, status, extra = {}) {
  const suffix = extra.error ? ` — ${extra.error}` : extra.skipped ? " (already done, skipped)" : "";
  console.log(`[finalize:${step}] ${status}${suffix}`);
  if (io && sessionId) {
    io.to(String(sessionId)).emit("report:progress", { step, status, ...extra });
  }
}

// Recomputes sha256 for every current attachment (sketch, both signatures,
// every photo) rather than trusting whatever accumulated in
// report.attachmentHashes over the session — see §5.4 step 6. A file that's
// gone missing from GridFS is skipped with a warning rather than failing
// the whole finalize (mirrors pdf.service.js's safeFetchBuffer forgiveness
// for the same class of already-broken state).
async function collectAttachmentHashes(report) {
  const entries = [];
  async function add(fileId, kind) {
    if (!fileId) return;
    try {
      const buffer = await storage.getFileBuffer(fileId);
      entries.push({ fileId, sha256: sha256(buffer), kind });
    } catch (err) {
      console.error(`[finalize] skipping missing attachment ${fileId} (${kind}): ${err.message}`);
    }
  }
  await add(report.sketch?.fileId, "sketch");
  await add(report.partyA?.signature?.fileId, "signature");
  await add(report.partyB?.signature?.fileId, "signature");
  for (const photo of report.photos || []) {
    await add(photo.fileId, "photo");
  }
  return entries;
}

// Runs (or resumes) the §5.4 finalize pipeline for one report. Safe to call
// repeatedly and from either party's client:
//  - status "sealed"                         -> no-op, returns the sealed report.
//  - status "signing"                        -> runs the full pipeline (steps 2-10).
//  - status "finalizing", pdf/bundle stored   -> a prior attempt got through
//                                                storage but the anchor call
//                                                (step 9) never confirmed —
//                                                retries ONLY steps 8-10.
//  - status "finalizing", pdf not yet stored  -> a prior attempt died before
//                                                anything durable was saved
//                                                (e.g. a process restart) —
//                                                re-runs the full pipeline.
//  - anything else                            -> rejected, not eligible yet.
async function runFinalize(reportId, io) {
  const key = String(reportId);
  if (_inFlight.has(key)) {
    throw new FinalizeError("finalize is already running for this report", "FINALIZE_IN_PROGRESS");
  }
  _inFlight.add(key);

  try {
    let report = await Report.findById(reportId);
    if (!report) throw new FinalizeError("report not found", "REPORT_NOT_FOUND");

    if (report.status === "sealed") {
      return { report, alreadySealed: true };
    }
    if (!["signing", "finalizing"].includes(report.status)) {
      throw new FinalizeError(
        `cannot finalize a report in status "${report.status}"`,
        "INVALID_STATUS"
      );
    }

    const sessionId = report.sessionId;

    // Step 1: validate. Re-checked on every attempt (fresh or retry) per
    // §5.4 — not just at the "signing" transition — as a defense-in-depth
    // floor independent of report-lock.service.js's own check.
    emitProgress(io, sessionId, "validate", "active");
    if (!bothPartiesSignedOff(report)) {
      emitProgress(io, sessionId, "validate", "error", {
        error: "both parties must confirm review and sign before finalizing",
      });
      throw new FinalizeError(
        "both parties must confirm review and sign before finalizing",
        "NOT_READY"
      );
    }
    emitProgress(io, sessionId, "validate", "done");

    const isAnchorRetry =
      report.status === "finalizing" && Boolean(report.pdf?.fileId) && Boolean(report.bundleHash);

    if (!isAnchorRetry) {
      // Step 2: lock (transition "signing" -> "finalizing"). Already
      // unwritable by clients either way (both statuses are in
      // LOCKED_STATUSES), so this is bookkeeping for the finalize state
      // machine itself, not an additional write guard.
      emitProgress(io, sessionId, "lock", "active");
      report.status = "finalizing";
      report.chain.lastError = null;
      await report.save();
      emitProgress(io, sessionId, "lock", "done");

      // Step 3: generate the PDF.
      emitProgress(io, sessionId, "pdf", "active");
      const pdfBuffer = await generateReportPdf(report);
      emitProgress(io, sessionId, "pdf", "done");

      // Step 4: hash it.
      emitProgress(io, sessionId, "hash", "active");
      const pdfHash = sha256(pdfBuffer);
      emitProgress(io, sessionId, "hash", "done");

      // Step 5: store it in GridFS.
      emitProgress(io, sessionId, "store", "active");
      const pdfFileId = await storage.storeBuffer(pdfBuffer, `report-${report._id}.pdf`, {
        contentType: "application/pdf",
        reportId: report._id,
      });
      emitProgress(io, sessionId, "store", "done");

      // Step 6: hash every attachment.
      emitProgress(io, sessionId, "attachments", "active");
      const attachmentHashes = await collectAttachmentHashes(report);
      emitProgress(io, sessionId, "attachments", "done");

      // Step 7: bundle hash.
      emitProgress(io, sessionId, "bundle", "active");
      const bundleHash = computeBundleHash(attachmentHashes);
      emitProgress(io, sessionId, "bundle", "done");

      report.pdf = { fileId: pdfFileId, sha256: pdfHash, generatedAt: new Date() };
      report.attachmentHashes = attachmentHashes;
      report.bundleHash = bundleHash;
      await report.save();
    } else {
      // Retry: steps 2-7 already happened and are durably stored. Replay
      // them as instantly-"done" progress events (rather than staying
      // silent) so a client's step list — which only tracks what it's
      // actually seen over the socket — still reflects reality instead of
      // showing "pending" forever for work that's genuinely finished.
      for (const step of ["lock", "pdf", "hash", "store", "attachments", "bundle"]) {
        emitProgress(io, sessionId, step, "done", { skipped: true });
      }
    }

    // Step 8: derive the on-chain report id.
    emitProgress(io, sessionId, "derive", "active");
    const reportId32 = chain.deriveReportId32(report._id);
    emitProgress(io, sessionId, "derive", "done");

    // Step 9: anchor on-chain, await the receipt.
    emitProgress(io, sessionId, "anchor", "active");
    let chainResult;
    try {
      chainResult = await chain.anchorReport(reportId32, `0x${report.pdf.sha256}`, `0x${report.bundleHash}`);
    } catch (err) {
      const message = err.shortMessage || err.reason || err.message || "anchor transaction failed";
      report.chain.lastError = message;
      await report.save();
      emitProgress(io, sessionId, "anchor", "error", { error: message });
      throw new FinalizeError(message, "ANCHOR_FAILED");
    }
    emitProgress(io, sessionId, "anchor", "done", { txHash: chainResult.txHash });

    report.chain = {
      txHash: chainResult.txHash,
      blockNumber: chainResult.blockNumber,
      contractAddress: chainResult.contractAddress,
      network: config.CHAIN_NETWORK,
      anchoredAt: new Date(),
      lastError: null,
    };

    // Step 10: seal.
    emitProgress(io, sessionId, "seal", "active");
    report.status = "sealed";
    report.sealedAt = new Date();
    await report.save();

    const session = sessionId ? await Session.findById(sessionId) : null;
    if (session && session.status !== "sealed") {
      session.status = "sealed";
      await session.save();
    }
    emitProgress(io, sessionId, "seal", "done");

    if (io && sessionId) {
      // Extends the minimal {pdfFileId, txHash, blockNumber} shape from
      // docs/master_plan.md §5.3 with the rest of the chain record, so
      // every connected client (not just whichever one's own POST happened
      // to complete the pipeline) can render the full sealed state —
      // network/contractAddress/anchoredAt — without a follow-up REST call.
      // See .claude/rules/backend.md and PROGRESS.md Decisions.
      io.to(String(sessionId)).emit("report:sealed", {
        pdfFileId: String(report.pdf.fileId),
        txHash: report.chain.txHash,
        blockNumber: report.chain.blockNumber,
        contractAddress: report.chain.contractAddress,
        network: report.chain.network,
        anchoredAt: report.chain.anchoredAt,
      });
    }

    return { report, sealed: true };
  } finally {
    _inFlight.delete(key);
  }
}

module.exports = { runFinalize, FinalizeError };
