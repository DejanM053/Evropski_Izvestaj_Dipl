const mongoose = require("mongoose");
const request = require("supertest");
const { io: ioClient } = require("socket.io-client");

// finalize.service.js's chain calls are mocked so this suite runs without a
// live Hardhat node — the contract layer itself is covered by
// `blockchain/test/registry.test.js` (npx hardhat test), and the real
// end-to-end anchor is exercised manually against docker-compose's hardhat
// service (see PROGRESS.md). This suite covers the pipeline's own state
// machine: gating, ordering, idempotency, and the anchor-only retry.
jest.mock("../src/services/chain.service", () => ({
  deriveReportId32: jest.fn((id) => "0x" + "11".repeat(32)),
  anchorReport: jest.fn(),
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

function waitForEvent(socket, event) {
  return new Promise((resolve) => socket.once(event, resolve));
}

describe("POST /api/reports/:id/finalize", () => {
  let app, server, io, baseUrl;

  beforeAll(async () => {
    await mongoose.connect(process.env.MONGO_URI);
    ({ app, server, io } = createApp());
    await new Promise((resolve) => server.listen(0, resolve));
    baseUrl = `http://localhost:${server.address().port}`;
  });

  afterAll(async () => {
    io.close();
    await new Promise((resolve) => server.close(resolve));
    await mongoose.disconnect();
  });

  beforeEach(async () => {
    await Session.deleteMany({});
    await Report.deleteMany({});
    chain.deriveReportId32.mockClear();
    chain.anchorReport.mockReset();
  });

  async function makeSignedOffReport(sessionOverrides = {}) {
    const sigAId = await storage.storeBuffer(PNG_BYTES, "sigA.png", { contentType: "image/png" });
    const sigBId = await storage.storeBuffer(PNG_BYTES, "sigB.png", { contentType: "image/png" });
    const report = await Report.create({
      status: "signing",
      partyA: { confirmedReview: true, signature: { fileId: sigAId, signedAt: new Date() } },
      partyB: { confirmedReview: true, signature: { fileId: sigBId, signedAt: new Date() } },
    });
    const session = await Session.create({
      sessionCode: "TESTFZ",
      status: "signing",
      reportId: report._id,
      expiresAt: new Date(Date.now() + 3600_000),
      ...sessionOverrides,
    });
    report.sessionId = session._id;
    await report.save();
    return { report, session };
  }

  it("rejects finalizing a report where both parties haven't signed off", async () => {
    const report = await Report.create({ status: "signing" });
    const res = await request(app).post(`/api/reports/${report._id}/finalize`).send();
    expect(res.status).toBe(409);
    expect(res.body.code).toBe("NOT_READY");
    expect((await Report.findById(report._id)).status).toBe("signing");
  });

  it("rejects finalizing a report that isn't signing/finalizing yet", async () => {
    const report = await Report.create({ status: "review" });
    const res = await request(app).post(`/api/reports/${report._id}/finalize`).send();
    expect(res.status).toBe(409);
    expect(res.body.code).toBe("INVALID_STATUS");
  });

  it("404s for an unknown report id", async () => {
    const res = await request(app)
      .post(`/api/reports/${new mongoose.Types.ObjectId()}/finalize`)
      .send();
    expect(res.status).toBe(404);
  });

  it("runs the full pipeline end to end and seals the report, broadcasting progress + report:sealed", async () => {
    chain.anchorReport.mockResolvedValue({
      txHash: "0xabc123",
      blockNumber: 42,
      contractAddress: "0xContract",
    });
    const { report, session } = await makeSignedOffReport();

    const socket = ioClient(baseUrl, { transports: ["websocket"], forceNew: true });
    const progressEvents = [];
    socket.on("report:progress", (event) => progressEvents.push(event));
    const sealedPromise = waitForEvent(socket, "report:sealed");
    await new Promise((resolve) => socket.on("connect", resolve));
    socket.emit("session:join", { sessionId: String(session._id), party: "A" });
    await waitForEvent(socket, "session:state");

    const res = await request(app).post(`/api/reports/${report._id}/finalize`).send();
    expect(res.status).toBe(200);
    expect(res.body.status).toBe("sealed");
    expect(res.body.chain.txHash).toBe("0xabc123");

    const sealed = await sealedPromise;
    expect(sealed).toEqual({
      pdfFileId: expect.any(String),
      txHash: "0xabc123",
      blockNumber: 42,
      contractAddress: "0xContract",
      network: expect.any(String),
      anchoredAt: expect.any(String),
    });

    const stepsSeen = progressEvents.map((e) => `${e.step}:${e.status}`);
    expect(stepsSeen).toEqual(
      expect.arrayContaining([
        "validate:done",
        "pdf:done",
        "hash:done",
        "store:done",
        "attachments:done",
        "bundle:done",
        "derive:done",
        "anchor:active",
        "anchor:done",
        "seal:done",
      ])
    );

    const finalReport = await Report.findById(report._id);
    expect(finalReport.status).toBe("sealed");
    expect(finalReport.sealedAt).not.toBeNull();
    expect(finalReport.pdf.fileId).not.toBeNull();
    expect(finalReport.bundleHash).not.toBeNull();
    expect((await Session.findById(session._id)).status).toBe("sealed");

    socket.close();
  });

  it("leaves the report in 'finalizing' with a stored error when the anchor call fails, then a retry re-anchors without regenerating the PDF", async () => {
    chain.anchorReport.mockRejectedValueOnce(new Error("insufficient funds for gas"));
    const { report } = await makeSignedOffReport();

    const failRes = await request(app).post(`/api/reports/${report._id}/finalize`).send();
    expect(failRes.status).toBe(502);
    expect(failRes.body.code).toBe("ANCHOR_FAILED");

    const afterFail = await Report.findById(report._id);
    expect(afterFail.status).toBe("finalizing");
    expect(afterFail.chain.lastError).toMatch(/insufficient funds/);
    expect(afterFail.pdf.fileId).not.toBeNull();
    const pdfFileIdAfterFail = String(afterFail.pdf.fileId);
    const generatedAtAfterFail = afterFail.pdf.generatedAt.getTime();

    chain.anchorReport.mockResolvedValueOnce({
      txHash: "0xretried",
      blockNumber: 99,
      contractAddress: "0xContract",
    });
    const retryRes = await request(app).post(`/api/reports/${report._id}/finalize`).send();
    expect(retryRes.status).toBe(200);
    expect(retryRes.body.status).toBe("sealed");
    expect(retryRes.body.chain.txHash).toBe("0xretried");
    // The retry must not have regenerated/re-stored the PDF.
    expect(String(retryRes.body.pdf.fileId)).toBe(pdfFileIdAfterFail);
    expect(new Date(retryRes.body.pdf.generatedAt).getTime()).toBe(generatedAtAfterFail);

    const sealed = await Report.findById(report._id);
    expect(sealed.status).toBe("sealed");
    expect(sealed.chain.lastError).toBeNull();
  });

  it("is idempotent once sealed — a repeat call returns the same sealed report without re-anchoring", async () => {
    chain.anchorReport.mockResolvedValue({ txHash: "0xonce", blockNumber: 1, contractAddress: "0xC" });
    const { report } = await makeSignedOffReport();

    await request(app).post(`/api/reports/${report._id}/finalize`).send();
    const second = await request(app).post(`/api/reports/${report._id}/finalize`).send();

    expect(second.status).toBe(200);
    expect(second.body.status).toBe("sealed");
    expect(second.body.chain.txHash).toBe("0xonce");
    expect(chain.anchorReport).toHaveBeenCalledTimes(1);
  });
});
