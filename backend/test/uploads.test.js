const mongoose = require("mongoose");
const request = require("supertest");
const { createApp } = require("../src/app");
const Session = require("../src/models/Session");
const Report = require("../src/models/Report");
const { sha256, computeBundleHash } = require("../src/services/hash.service");

// A minimal but valid 1x1 PNG, used as upload payload across tests.
const PNG_BYTES = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
  "base64"
);
const JPEG_MIME = "image/jpeg";

describe("hash.service", () => {
  it("sha256 is stable for identical bytes", () => {
    expect(sha256(PNG_BYTES)).toBe(sha256(Buffer.from(PNG_BYTES)));
  });

  it("sha256 changes when a single byte is tampered", () => {
    const tampered = Buffer.from(PNG_BYTES);
    tampered[0] ^= 0xff;
    expect(sha256(tampered)).not.toBe(sha256(PNG_BYTES));
  });

  it("computeBundleHash is stable across reordered inserts", () => {
    const hashes = [sha256(Buffer.from("a")), sha256(Buffer.from("b")), sha256(Buffer.from("c"))];
    const forward = computeBundleHash(hashes.map((sha256) => ({ sha256 })));
    const shuffled = computeBundleHash(
      [hashes[2], hashes[0], hashes[1]].map((sha256) => ({ sha256 }))
    );
    expect(forward).toBe(shuffled);
  });

  it("computeBundleHash changes if any attachment hash changes", () => {
    const base = computeBundleHash([{ sha256: sha256(Buffer.from("a")) }, { sha256: sha256(Buffer.from("b")) }]);
    const tampered = computeBundleHash([
      { sha256: sha256(Buffer.from("a")) },
      { sha256: sha256(Buffer.from("B")) },
    ]);
    expect(base).not.toBe(tampered);
  });
});

describe("File uploads (GridFS + hashing)", () => {
  let app, server, reportId;

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
    const report = await Report.create({});
    reportId = report._id.toString();
  });

  describe("POST /api/reports/:id/photos", () => {
    it("stores the file, returns a stable sha256, and records attachmentHashes", async () => {
      const res = await request(app)
        .post(`/api/reports/${reportId}/photos`)
        .field("party", "A")
        .field("caption", "front bumper")
        .attach("file", PNG_BYTES, { filename: "photo.png", contentType: "image/png" });

      expect(res.status).toBe(201);
      expect(res.body.sha256).toBe(sha256(PNG_BYTES));
      expect(res.body.fileId).toBeDefined();
      expect(res.body.caption).toBe("front bumper");
      expect(res.body.party).toBe("A");

      const report = await Report.findById(reportId);
      expect(report.photos).toHaveLength(1);
      expect(report.photos[0].fileId.toString()).toBe(res.body.fileId);
      expect(report.attachmentHashes).toHaveLength(1);
      expect(report.attachmentHashes[0]).toMatchObject({ sha256: sha256(PNG_BYTES), kind: "photo" });
    });

    it("uploading the same bytes twice yields an identical hash", async () => {
      const first = await request(app)
        .post(`/api/reports/${reportId}/photos`)
        .field("party", "A")
        .attach("file", PNG_BYTES, { filename: "a.png", contentType: "image/png" });
      const second = await request(app)
        .post(`/api/reports/${reportId}/photos`)
        .field("party", "B")
        .attach("file", PNG_BYTES, { filename: "b.png", contentType: "image/png" });

      expect(first.body.sha256).toBe(second.body.sha256);
      expect(first.body.fileId).not.toBe(second.body.fileId);
    });

    it("rejects a non-image mime type", async () => {
      const res = await request(app)
        .post(`/api/reports/${reportId}/photos`)
        .field("party", "A")
        .attach("file", Buffer.from("not an image"), {
          filename: "notes.txt",
          contentType: "text/plain",
        });

      expect(res.status).toBe(415);
    });

    it("rejects a file over the 10MB cap", async () => {
      const oversized = Buffer.alloc(10 * 1024 * 1024 + 1);
      const res = await request(app)
        .post(`/api/reports/${reportId}/photos`)
        .field("party", "A")
        .attach("file", oversized, { filename: "big.png", contentType: "image/png" });

      expect(res.status).toBe(413);
    });

    it("rejects an upload without a recognized party", async () => {
      const res = await request(app)
        .post(`/api/reports/${reportId}/photos`)
        .field("party", "C")
        .attach("file", PNG_BYTES, { filename: "a.png", contentType: "image/png" });

      expect(res.status).toBe(400);
    });

    it("rejects uploads to a sealed report", async () => {
      await Report.findByIdAndUpdate(reportId, { status: "sealed" });

      const res = await request(app)
        .post(`/api/reports/${reportId}/photos`)
        .field("party", "A")
        .attach("file", PNG_BYTES, { filename: "a.png", contentType: "image/png" });

      expect(res.status).toBe(409);
    });
  });

  describe("DELETE /api/reports/:id/photos/:fileId", () => {
    it("removes the photo, its attachmentHashes entry, and the GridFS blob", async () => {
      const upload = await request(app)
        .post(`/api/reports/${reportId}/photos`)
        .field("party", "A")
        .attach("file", PNG_BYTES, { filename: "photo.png", contentType: "image/png" });
      const fileId = upload.body.fileId;

      const res = await request(app).delete(`/api/reports/${reportId}/photos/${fileId}`);
      expect(res.status).toBe(204);

      const report = await Report.findById(reportId);
      expect(report.photos).toHaveLength(0);
      expect(report.attachmentHashes).toHaveLength(0);

      const streamed = await request(app).get(`/api/files/${fileId}`);
      expect(streamed.status).toBe(404);
    });

    it("returns 404 for a photo that doesn't exist on this report", async () => {
      const res = await request(app).delete(
        `/api/reports/${reportId}/photos/${new mongoose.Types.ObjectId()}`
      );
      expect(res.status).toBe(404);
    });

    it("rejects deleting from a sealed report", async () => {
      const upload = await request(app)
        .post(`/api/reports/${reportId}/photos`)
        .field("party", "A")
        .attach("file", PNG_BYTES, { filename: "photo.png", contentType: "image/png" });
      await Report.findByIdAndUpdate(reportId, { status: "sealed" });

      const res = await request(app).delete(`/api/reports/${reportId}/photos/${upload.body.fileId}`);
      expect(res.status).toBe(409);
    });
  });

  describe("POST /api/reports/:id/sketch", () => {
    it("stores the sketch and replaces a prior sketch's attachmentHashes entry", async () => {
      const first = await request(app)
        .post(`/api/reports/${reportId}/sketch`)
        .attach("file", PNG_BYTES, { filename: "sketch.png", contentType: "image/png" });
      expect(first.status).toBe(201);

      const jpegBytes = Buffer.from(PNG_BYTES); // reuse bytes, different declared mime
      const second = await request(app)
        .post(`/api/reports/${reportId}/sketch`)
        .attach("file", jpegBytes, { filename: "sketch2.jpg", contentType: JPEG_MIME });
      expect(second.status).toBe(201);

      const report = await Report.findById(reportId);
      expect(report.sketch.fileId.toString()).toBe(second.body.fileId);
      expect(report.attachmentHashes.filter((a) => a.kind === "sketch")).toHaveLength(1);
    });
  });

  describe("POST /api/reports/:id/signature", () => {
    it("stores a per-party signature with signedAt", async () => {
      const res = await request(app)
        .post(`/api/reports/${reportId}/signature`)
        .field("party", "A")
        .attach("file", PNG_BYTES, { filename: "sig.png", contentType: "image/png" });

      expect(res.status).toBe(201);
      expect(res.body.party).toBe("A");
      expect(res.body.signedAt).toBeDefined();

      const report = await Report.findById(reportId);
      expect(report.partyA.signature.fileId.toString()).toBe(res.body.fileId);
      expect(report.partyB.signature.fileId).toBeNull();
    });
  });

  describe("GET /api/files/:fileId", () => {
    it("streams the file back byte-identical", async () => {
      const upload = await request(app)
        .post(`/api/reports/${reportId}/photos`)
        .field("party", "A")
        .attach("file", PNG_BYTES, { filename: "photo.png", contentType: "image/png" });

      const res = await request(app)
        .get(`/api/files/${upload.body.fileId}`)
        .buffer(true)
        .parse((res, callback) => {
          const chunks = [];
          res.on("data", (chunk) => chunks.push(chunk));
          res.on("end", () => callback(null, Buffer.concat(chunks)));
        });

      expect(res.status).toBe(200);
      expect(res.headers["content-type"]).toBe("image/png");
      expect(Buffer.compare(res.body, PNG_BYTES)).toBe(0);
      expect(sha256(res.body)).toBe(upload.body.sha256);
    });

    it("returns 404 for an unknown file id", async () => {
      const res = await request(app).get(`/api/files/${new mongoose.Types.ObjectId()}`);
      expect(res.status).toBe(404);
    });
  });
});
