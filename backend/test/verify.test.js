const mongoose = require("mongoose");
const request = require("supertest");

// Same mocking approach as finalize.test.js: this suite exercises
// verify.service.js's own logic (recompute-from-bytes, three-way verdict),
// not a live Hardhat node — chain reads are stubbed to return whatever the
// finalize pipeline actually stored, i.e. "the chain faithfully remembers
// what was anchored", so a real byte-level GridFS tamper is what has to
// produce the mismatch, exactly like the live demo (docs/master_plan.md §9).
jest.mock("../src/services/chain.service", () => ({
  deriveReportId32: jest.fn((id) => "0x" + "33".repeat(32)),
  anchorReport: jest.fn(),
  getOnChainRecord: jest.fn(),
}));
const chain = require("../src/services/chain.service");

const { createApp } = require("../src/app");
const Session = require("../src/models/Session");
const Report = require("../src/models/Report");
const storage = require("../src/services/storage.service");

const PNG_BYTES = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
  "base64"
);

describe("GET /api/reports/:id/verify", () => {
  let app, server;

  beforeAll(async () => {
    await mongoose.connect(process.env.MONGO_URI);
    ({ app, server } = createApp());
    await new Promise((resolve) => server.listen(0, resolve));
  });

  afterAll(async () => {
    await new Promise((resolve) => server.close(resolve));
    await mongoose.disconnect();
  });

  beforeEach(async () => {
    await Session.deleteMany({});
    await Report.deleteMany({});
    chain.deriveReportId32.mockClear();
    chain.anchorReport.mockReset();
    chain.getOnChainRecord.mockReset();
  });

  // Builds a fully signed-off report (sketch + 1 photo + both signatures),
  // runs it through the real POST /finalize pipeline (anchorReport mocked),
  // and points getOnChainRecord at exactly whatever the pipeline stored —
  // i.e. simulates a chain that faithfully remembers what was anchored, so
  // any later mismatch has to come from a genuine post-finalize GridFS
  // mutation, not a rigged mock.
  async function makeSealedReport() {
    const sigAId = await storage.storeBuffer(PNG_BYTES, "sigA.png", { contentType: "image/png" });
    const sigBId = await storage.storeBuffer(PNG_BYTES, "sigB.png", { contentType: "image/png" });
    const sketchId = await storage.storeBuffer(PNG_BYTES, "sketch.png", { contentType: "image/png" });
    const photoId = await storage.storeBuffer(PNG_BYTES, "photo1.png", { contentType: "image/png" });

    const report = await Report.create({
      status: "signing",
      partyA: { confirmedReview: true, signature: { fileId: sigAId, signedAt: new Date() } },
      partyB: { confirmedReview: true, signature: { fileId: sigBId, signedAt: new Date() } },
      sketch: { fileId: sketchId },
      photos: [{ fileId: photoId, caption: "", party: "A", takenAt: new Date() }],
    });
    const session = await Session.create({
      sessionCode: "TESTVF",
      status: "signing",
      reportId: report._id,
      expiresAt: new Date(Date.now() + 3600_000),
    });
    report.sessionId = session._id;
    await report.save();

    chain.anchorReport.mockResolvedValue({
      txHash: "0xsealedtx",
      blockNumber: 7,
      contractAddress: "0xContract",
    });
    const finalizeRes = await request(app).post(`/api/reports/${report._id}/finalize`).send();
    expect(finalizeRes.status).toBe(200);
    expect(finalizeRes.body.status).toBe("sealed");

    const sealed = await Report.findById(report._id);
    chain.getOnChainRecord.mockResolvedValue({
      pdfHash: `0x${sealed.pdf.sha256}`,
      bundleHash: `0x${sealed.bundleHash}`,
      timestamp: BigInt(Math.floor(Date.now() / 1000)),
      submitter: "0xSubmitter",
    });

    return { report: sealed, photoId, sketchId };
  }

  it("verdicts NOT_ANCHORED for a report that was never finalized", async () => {
    const report = await Report.create({ status: "filling" });
    const res = await request(app).get(`/api/reports/${report._id}/verify`);
    expect(res.status).toBe(200);
    expect(res.body.verdict).toBe("NOT_ANCHORED");
    expect(res.body.pdf.match).toBe(false);
    expect(res.body.bundle.match).toBe(false);
    expect(chain.getOnChainRecord).not.toHaveBeenCalled();
  });

  it("verdicts VERIFIED for an untouched sealed report", async () => {
    const { report } = await makeSealedReport();

    const res = await request(app).get(`/api/reports/${report._id}/verify`);
    expect(res.status).toBe(200);
    expect(res.body.verdict).toBe("VERIFIED");
    expect(res.body.pdf.match).toBe(true);
    expect(res.body.pdf.recomputedHash).toBe(res.body.pdf.onChainHash);
    expect(res.body.bundle.match).toBe(true);
    expect(res.body.attachments).toHaveLength(4); // sketch + 2 signatures + 1 photo
    expect(res.body.attachments.every((a) => a.match === true)).toBe(true);
    expect(res.body.chain.txHash).toBe("0xsealedtx");
  });

  it("verdicts TAMPERED with pdf.match false after the stored PDF bytes are mutated in GridFS", async () => {
    const { report } = await makeSealedReport();

    const pdfBuffer = await storage.getFileBuffer(report.pdf.fileId);
    pdfBuffer[0] ^= 0xff; // flip one byte, exactly what scripts/tamper.js does
    await storage.overwriteFile(report.pdf.fileId, pdfBuffer);

    const res = await request(app).get(`/api/reports/${report._id}/verify`);
    expect(res.status).toBe(200);
    expect(res.body.verdict).toBe("TAMPERED");
    expect(res.body.pdf.match).toBe(false);
    expect(res.body.pdf.recomputedHash).not.toBe(res.body.pdf.onChainHash);
    // The Mongo-stored hash is untouched — it's the recomputed-vs-chain
    // comparison that catches this, not a stale "storedHash" field.
    expect(res.body.pdf.storedHash).toBe(res.body.pdf.onChainHash);
    // Only the PDF was mutated — the attachment bundle is unaffected.
    expect(res.body.bundle.match).toBe(true);
    expect(res.body.attachments.every((a) => a.match === true)).toBe(true);
  });

  it("names the specific file when one attachment's bytes are swapped", async () => {
    const { report, photoId } = await makeSealedReport();

    await storage.overwriteFile(photoId, Buffer.from("not the original photo bytes"));

    const res = await request(app).get(`/api/reports/${report._id}/verify`);
    expect(res.status).toBe(200);
    expect(res.body.verdict).toBe("TAMPERED");
    // The PDF itself wasn't touched.
    expect(res.body.pdf.match).toBe(true);
    // The bundle hash (which aggregates every attachment) no longer matches.
    expect(res.body.bundle.match).toBe(false);
    const photoEntry = res.body.attachments.find((a) => a.fileId === String(photoId));
    expect(photoEntry).toBeDefined();
    expect(photoEntry.kind).toBe("photo");
    expect(photoEntry.match).toBe(false);
    expect(res.body.attachments.filter((a) => a.match === false)).toHaveLength(1);
  });

  it("404s for an unknown report id", async () => {
    const res = await request(app).get(`/api/reports/${new mongoose.Types.ObjectId()}/verify`);
    expect(res.status).toBe(404);
    expect(res.body.code).toBe("REPORT_NOT_FOUND");
  });
});
