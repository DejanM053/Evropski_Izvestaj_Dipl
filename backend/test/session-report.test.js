const mongoose = require("mongoose");
const request = require("supertest");
const { io: ioClient } = require("socket.io-client");
const { createApp } = require("../src/app");
const Session = require("../src/models/Session");
const Report = require("../src/models/Report");
const { ALPHABET } = require("../src/services/session-code.service");

const CODE_REGEX = new RegExp(`^[${ALPHABET}]{6}$`);

function waitForEvent(socket, event) {
  return new Promise((resolve) => socket.once(event, resolve));
}

describe("Session + Report data layer and real-time sync", () => {
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
  });

  async function createAndJoinSession() {
    const createRes = await request(app).post("/api/sessions").send();
    const { sessionId, sessionCode, reportId } = createRes.body;
    await request(app).post(`/api/sessions/${sessionCode}/join`).send();
    return { sessionId, sessionCode, reportId };
  }

  function connectClient(baseUrlArg) {
    return ioClient(baseUrlArg, { transports: ["websocket"], forceNew: true });
  }

  async function joinSocket(socket, sessionId, party) {
    const statePromise = waitForEvent(socket, "session:state");
    socket.emit("session:join", { sessionId, party });
    return statePromise;
  }

  describe("POST /api/sessions", () => {
    it("creates a session with a unique 6-char human-readable code and a linked report", async () => {
      const res = await request(app).post("/api/sessions").send();

      expect(res.status).toBe(201);
      expect(res.body.sessionId).toBeDefined();
      expect(res.body.sessionCode).toMatch(CODE_REGEX);
      expect(res.body.reportId).toBeDefined();

      const session = await Session.findById(res.body.sessionId);
      expect(session.status).toBe("waiting");
      expect(session.sessionCode).toBe(res.body.sessionCode);

      const report = await Report.findById(res.body.reportId);
      expect(report).not.toBeNull();
      expect(report.sessionId.toString()).toBe(res.body.sessionId);
    });

    it("generates codes without ambiguous characters (0, O, 1, I, L)", async () => {
      for (let i = 0; i < 20; i++) {
        const res = await request(app).post("/api/sessions").send();
        expect(res.body.sessionCode).not.toMatch(/[01OIL]/);
      }
    });
  });

  describe("POST /api/sessions/:code/join", () => {
    it("joins as party B and advances status to joined", async () => {
      const createRes = await request(app).post("/api/sessions").send();
      const { sessionCode, sessionId } = createRes.body;

      const joinRes = await request(app).post(`/api/sessions/${sessionCode}/join`).send();
      expect(joinRes.status).toBe(200);
      expect(joinRes.body.sessionId).toBe(sessionId);

      const session = await Session.findById(sessionId);
      expect(session.status).toBe("joined");
    });

    it("rejects joining a session that already has both parties", async () => {
      const createRes = await request(app).post("/api/sessions").send();
      const { sessionCode } = createRes.body;

      await request(app).post(`/api/sessions/${sessionCode}/join`).send();
      const secondJoin = await request(app).post(`/api/sessions/${sessionCode}/join`).send();

      expect(secondJoin.status).toBe(409);
    });

    it("rejects an unknown session code", async () => {
      const res = await request(app).post("/api/sessions/ZZZZZZ/join").send();
      expect(res.status).toBe(404);
    });
  });

  describe("GET /api/sessions/:id and GET /api/reports/:id", () => {
    it("returns the current session + report state", async () => {
      const { sessionId, reportId } = await createAndJoinSession();

      const res = await request(app).get(`/api/sessions/${sessionId}`);
      expect(res.status).toBe(200);
      expect(res.body.session._id).toBe(sessionId);
      expect(res.body.report._id).toBe(reportId);
    });

    it("returns the full report JSON", async () => {
      const { reportId } = await createAndJoinSession();

      const res = await request(app).get(`/api/reports/${reportId}`);
      expect(res.status).toBe(200);
      expect(res.body._id).toBe(reportId);
      expect(res.body.status).toBe("waiting");
    });
  });

  describe("GET /api/reports", () => {
    it("lists reports and filters by plate", async () => {
      const { reportId } = await createAndJoinSession();
      await Report.findByIdAndUpdate(reportId, { "partyA.vehicle.plate": "AB-123-CD" });

      const all = await request(app).get("/api/reports");
      expect(all.status).toBe(200);
      expect(all.body.length).toBeGreaterThanOrEqual(1);

      const filtered = await request(app).get("/api/reports?plate=AB-123-CD");
      expect(filtered.body.map((r) => r._id)).toContain(reportId);

      const noMatch = await request(app).get("/api/reports?plate=NOPE");
      expect(noMatch.body.map((r) => r._id)).not.toContain(reportId);
    });
  });

  describe("real-time sync over Socket.IO", () => {
    let sessionId, reportId, socketA, socketB;

    beforeEach(async () => {
      ({ sessionId, reportId } = await createAndJoinSession());
      socketA = connectClient(baseUrl);
      socketB = connectClient(baseUrl);
      await Promise.all([
        joinSocket(socketA, sessionId, "A"),
        joinSocket(socketB, sessionId, "B"),
      ]);
    });

    afterEach(() => {
      socketA.close();
      socketB.close();
    });

    it("delivers session:state with the current report snapshot on join", async () => {
      const socketC = connectClient(baseUrl);
      const state = await joinSocket(socketC, sessionId, "A");

      expect(state.session._id).toBe(sessionId);
      expect(state.report._id).toBe(reportId);
      socketC.close();
    });

    it("propagates patches from both parties to the whole room", async () => {
      const patchedOnB = waitForEvent(socketB, "report:patched");
      socketA.emit("report:patch", { path: "partyA.vehicle.plate", value: "AAA-111" });
      const eventOnB = await patchedOnB;
      expect(eventOnB).toEqual({ path: "partyA.vehicle.plate", value: "AAA-111", by: "A" });

      const patchedOnA = waitForEvent(socketA, "report:patched");
      socketB.emit("report:patch", { path: "partyB.vehicle.plate", value: "BBB-222" });
      const eventOnA = await patchedOnA;
      expect(eventOnA).toEqual({ path: "partyB.vehicle.plate", value: "BBB-222", by: "B" });

      const report = await Report.findById(reportId);
      expect(report.partyA.vehicle.plate).toBe("AAA-111");
      expect(report.partyB.vehicle.plate).toBe("BBB-222");
    });

    // Regression test for a bug found via live testing: the mobile app's
    // "fill sample data" button fires ~18 report:patch messages back-to-back
    // with no pacing. Before report-mutex.service.js's per-report
    // serialization, concurrent patches into different leaves of a
    // not-yet-existing nested subdocument (partyA.vehicle/partyA.insurer
    // start out absent) raced: each patch's own fetch→set→save cycle
    // fetched a snapshot before the others had committed, and Mongoose
    // marking the whole parent path (not the leaf) dirty for a brand-new
    // subdocument meant their saves generated conflicting whole-object
    // $set operations that silently clobbered each other — reproduced
    // reliably (first try) with a standalone script mimicking this exact
    // burst against the real dev stack. `partyA.vehicle` ended up missing
    // entirely and `partyA.insurer` had only its last-patched field.
    it("keeps every field from a burst of concurrent patches into a not-yet-existing subdocument", async () => {
      const paths = [
        "partyA.vehicle.make",
        "partyA.vehicle.model",
        "partyA.vehicle.plate",
        "partyA.vehicle.country",
        "partyA.vehicle.vin",
        "partyA.insurer.company",
        "partyA.insurer.policyNumber",
        "partyA.insurer.greenCardNumber",
        "partyA.insurer.agency",
      ];
      const received = [];
      const allPatched = new Promise((resolve) => {
        socketB.on("report:patched", (event) => {
          received.push(event.path);
          if (received.length === paths.length) resolve();
        });
      });
      paths.forEach((path, i) => socketA.emit("report:patch", { path, value: `v${i}` }));
      await allPatched;

      const report = await Report.findById(reportId);
      expect(report.partyA.vehicle.make).toBe("v0");
      expect(report.partyA.vehicle.model).toBe("v1");
      expect(report.partyA.vehicle.plate).toBe("v2");
      expect(report.partyA.vehicle.country).toBe("v3");
      expect(report.partyA.vehicle.vin).toBe("v4");
      expect(report.partyA.insurer.company).toBe("v5");
      expect(report.partyA.insurer.policyNumber).toBe("v6");
      expect(report.partyA.insurer.greenCardNumber).toBe("v7");
      expect(report.partyA.insurer.agency).toBe("v8");
    });

    it("allows either party to patch a shared subtree (accident.*)", async () => {
      const patchedOnA = waitForEvent(socketA, "report:patched");
      socketB.emit("report:patch", { path: "accident.location.address", value: "Main St 1" });
      await patchedOnA;

      const report = await Report.findById(reportId);
      expect(report.accident.location.address).toBe("Main St 1");
    });

    it("resyncs full state via session:state after a reconnect", async () => {
      const patched = waitForEvent(socketB, "report:patched");
      socketA.emit("report:patch", { path: "partyA.vehicle.plate", value: "REJOIN-1" });
      await patched;

      socketA.close();
      const reconnected = connectClient(baseUrl);
      const state = await joinSocket(reconnected, sessionId, "A");

      expect(state.report.partyA.vehicle.plate).toBe("REJOIN-1");
      reconnected.close();
    });

    it("rejects a patch into the other party's subtree", async () => {
      const errorOnA = waitForEvent(socketA, "session:error");
      socketA.emit("report:patch", { path: "partyB.vehicle.plate", value: "HACKED" });
      const error = await errorOnA;

      expect(error.code).toBe("FORBIDDEN_PATCH");

      const report = await Report.findById(reportId);
      expect(report.partyB.vehicle.plate).toBeUndefined();
    });

    it("rejects a patch once the report is sealed", async () => {
      await Report.findByIdAndUpdate(reportId, { status: "sealed" });

      const errorOnA = waitForEvent(socketA, "session:error");
      socketA.emit("report:patch", { path: "partyA.vehicle.plate", value: "TOO-LATE" });
      const error = await errorOnA;

      expect(error.code).toBe("REPORT_SEALED");
    });

    it("locks the report once both parties have confirmed review and signed, emitting report:locked", async () => {
      // Signatures are uploaded via REST in real usage (uploads.js), but the
      // lock condition only cares about the persisted fields, so setting
      // them directly here keeps this test focused on the socket-side half
      // of the trigger (confirmedReview).
      await Report.findByIdAndUpdate(reportId, {
        "partyA.signature.fileId": new mongoose.Types.ObjectId(),
        "partyA.signature.signedAt": new Date(),
        "partyB.signature.fileId": new mongoose.Types.ObjectId(),
        "partyB.signature.signedAt": new Date(),
      });

      const patchedOnB = waitForEvent(socketB, "report:patched");
      socketA.emit("report:patch", { path: "partyA.confirmedReview", value: true });
      await patchedOnB;

      // Not locked yet — only one party has confirmed.
      expect((await Report.findById(reportId)).status).not.toBe("signing");

      const lockedOnA = waitForEvent(socketA, "report:locked");
      const lockedOnB = waitForEvent(socketB, "report:locked");
      socketB.emit("report:patch", { path: "partyB.confirmedReview", value: true });
      await Promise.all([lockedOnA, lockedOnB]);

      const report = await Report.findById(reportId);
      expect(report.status).toBe("signing");
      const session = await Session.findById(sessionId);
      expect(session.status).toBe("signing");

      const errorOnA = waitForEvent(socketA, "session:error");
      socketA.emit("report:patch", { path: "partyA.vehicle.plate", value: "TOO-LATE" });
      const error = await errorOnA;
      expect(error.code).toBe("SESSION_LOCKED");
    });

    it("freezes a party's own subtree the instant they sign, before the other party has", async () => {
      await Report.findByIdAndUpdate(reportId, {
        "partyA.confirmedReview": true,
        "partyA.signature.fileId": new mongoose.Types.ObjectId(),
        "partyA.signature.signedAt": new Date(),
      });

      // Report/session aren't locked yet (only A has signed off) — this is
      // a per-party freeze, distinct from the full-report SESSION_LOCKED
      // case above.
      const errorOnA = waitForEvent(socketA, "session:error");
      socketA.emit("report:patch", { path: "partyA.vehicle.plate", value: "TOO-LATE" });
      const error = await errorOnA;
      expect(error.code).toBe("PARTY_LOCKED");

      const report = await Report.findById(reportId);
      expect(report.partyA.vehicle.plate).toBeUndefined();
      const session = await Session.findById(sessionId);
      expect(session.status).not.toBe("signing");
    });

    it("still allows the not-yet-signed party to patch their own subtree", async () => {
      await Report.findByIdAndUpdate(reportId, {
        "partyA.confirmedReview": true,
        "partyA.signature.fileId": new mongoose.Types.ObjectId(),
        "partyA.signature.signedAt": new Date(),
      });

      const patchedOnA = waitForEvent(socketA, "report:patched");
      socketB.emit("report:patch", { path: "partyB.vehicle.plate", value: "STILL-OK" });
      await patchedOnA;

      const report = await Report.findById(reportId);
      expect(report.partyB.vehicle.plate).toBe("STILL-OK");
    });

    it("still allows editing shared subtrees after one party has signed", async () => {
      await Report.findByIdAndUpdate(reportId, {
        "partyA.confirmedReview": true,
        "partyA.signature.fileId": new mongoose.Types.ObjectId(),
        "partyA.signature.signedAt": new Date(),
      });

      const patchedOnB = waitForEvent(socketB, "report:patched");
      socketA.emit("report:patch", { path: "accident.location.address", value: "Still editable" });
      await patchedOnB;

      const report = await Report.findById(reportId);
      expect(report.accident.location.address).toBe("Still editable");
    });
  });
});
