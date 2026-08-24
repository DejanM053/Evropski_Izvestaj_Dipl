const path = require("path");
const mongoose = require("mongoose");
const request = require("supertest");
const fontkit = require("fontkit");
const { createApp } = require("../src/app");
const Report = require("../src/models/Report");
const storage = require("../src/services/storage.service");
const { generateReportPdf } = require("../src/services/pdf.service");

// A minimal but valid 1x1 PNG, used as sketch/photo/signature payloads.
const PNG_BYTES = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
  "base64"
);

function isPdf(buffer) {
  return Buffer.isBuffer(buffer) && buffer.subarray(0, 5).toString("latin1") === "%PDF-";
}

// pdfkit emits one "/Type /Page" object per page plus one "/Type /Pages"
// tree root — counting the former (and excluding the latter) is a good
// enough proxy for page count without pulling in a PDF parser just for tests.
function countPages(buffer) {
  const text = buffer.toString("latin1");
  const matches = text.match(/\/Type\s*\/Page[^s]/g);
  return matches ? matches.length : 0;
}


describe("pdf.service", () => {
  beforeAll(async () => {
    await mongoose.connect(process.env.MONGO_URI);
  });

  afterAll(async () => {
    await mongoose.disconnect();
  });

  beforeEach(async () => {
    await Report.deleteMany({});
  });

  it("generates a valid single-page PDF from a bare-minimum report (every optional field missing)", async () => {
    const report = await Report.create({});
    const buffer = await generateReportPdf(report);

    expect(isPdf(buffer)).toBe(true);
    expect(countPages(buffer)).toBeGreaterThanOrEqual(1);
  });

  it("handles zero photos, a missing sketch, and missing signatures without crashing", async () => {
    const report = await Report.create({
      accident: { dateTime: new Date("2026-01-15T10:30:00Z"), location: { address: "Test St 1" } },
    });
    const buffer = await generateReportPdf(report);
    expect(isPdf(buffer)).toBe(true);
  });

  it("wraps very long remarks instead of overflowing or crashing", async () => {
    const longText = "Vrlo dugačak opis štete koji se ponavlja. ".repeat(200);
    const report = await Report.create({
      partyA: { remarks: longText, visibleDamage: longText },
    });
    const buffer = await generateReportPdf(report);
    expect(isPdf(buffer)).toBe(true);
    // A page's worth of repeated text at this length should force at least
    // one extra page via pdfkit's own text-flow pagination — bounded above
    // too (not just `> 1`), so a regression that silently tacks on extra
    // blank pages (as the footer-stamping bug once did) would fail this.
    const pages = countPages(buffer);
    expect(pages).toBeGreaterThan(1);
    expect(pages).toBeLessThanOrEqual(4);
  });

  it("paginates a photo appendix that doesn't fit on one page", async () => {
    const report = await Report.create({});
    const photoCount = 14;
    for (let i = 0; i < photoCount; i++) {
      const fileId = await storage.storeBuffer(PNG_BYTES, `photo-${i}.png`, { contentType: "image/png" });
      report.photos.push({ fileId, caption: `Fotografija ${i}`, party: i % 2 === 0 ? "A" : "B", takenAt: new Date() });
    }
    await report.save();

    const buffer = await generateReportPdf(report);
    expect(isPdf(buffer)).toBe(true);
    // 14 photos at 2/row is 7 rows — bounded above too, same regression
    // guard as the long-remarks test above.
    const pages = countPages(buffer);
    expect(pages).toBeGreaterThan(1);
    expect(pages).toBeLessThanOrEqual(6);
  });

  it("embeds a fully filled report's sketch, photos, and both signatures without excess blank pages", async () => {
    const sketchId = await storage.storeBuffer(PNG_BYTES, "sketch.png", { contentType: "image/png" });
    const photoId = await storage.storeBuffer(PNG_BYTES, "photo.png", { contentType: "image/png" });
    const sigAId = await storage.storeBuffer(PNG_BYTES, "sigA.png", { contentType: "image/png" });
    const sigBId = await storage.storeBuffer(PNG_BYTES, "sigB.png", { contentType: "image/png" });

    const report = await Report.create({
      status: "signing",
      accident: {
        dateTime: new Date("2026-02-01T08:00:00Z"),
        location: { address: "Bulevar Oslobođenja 10", lat: 45.2671, lng: 19.8335 },
        injuries: false,
        otherVehicleDamage: true,
        witnesses: [{ name: "Petar Petrović", phone: "0601234567" }],
      },
      partyA: {
        driver: { firstName: "Dejan", lastName: "Mihajlović", phone: "0611111111" },
        vehicle: { make: "Yugo", model: "Zastava", plate: "NS-123-AB" },
        insurer: { company: "DDOR" },
        circumstances: [0, 5, 9],
        visibleDamage: "Ogrebotina na braniku",
        remarks: "Nema dodatnih napomena",
        confirmedReview: true,
        signature: { fileId: sigAId, signedAt: new Date() },
      },
      partyB: {
        driver: { firstName: "Mihajlo", lastName: "Dejanović", phone: "0622222222" },
        vehicle: { make: "Fiat", model: "Punto", plate: "BG-456-CD" },
        insurer: { company: "Generali" },
        circumstances: [2, 4],
        confirmedReview: true,
        signature: { fileId: sigBId, signedAt: new Date() },
      },
      sketch: { fileId: sketchId },
      photos: [{ fileId: photoId, caption: "Prednji branik", party: "A", takenAt: new Date() }],
    });

    const buffer = await generateReportPdf(report);
    expect(isPdf(buffer)).toBe(true);

    // Regression guard for the footer-stamping bug (pdfkit's own overflow
    // check firing on absolutely-positioned text drawn inside the reserved
    // bottom-margin strip, silently appending a blank page after every
    // real page — see stampFooterOnAllPages's comment): this fixture's
    // content is known to need exactly 3 pages (party/circumstances grid,
    // damage/remarks/witnesses/sketch/photos, signatures — the embedded
    // IBM Plex fonts run slightly wider than Helvetica did, so this
    // legitimately needs one more page than it used to), not that plus
    // however many blank ones the bug used to tack on.
    expect(countPages(buffer)).toBe(3);
  });
});

describe("Serbian Latin diacritics (č, ć, š, đ, ž)", () => {
  // pdfkit's standard 14 fonts only support WinAnsiEncoding, which has no
  // code points for č/ć/đ (Š/š and Ž/ž happen to be in WinAnsi, but the
  // other three aren't) — text using them silently dropped the character
  // or rendered the wrong glyph. Fixed by embedding the same IBM Plex font
  // files the Flutter app already bundles. This checks the actual font
  // files pdf.service.js registers, not the PDF output — pdfkit embeds
  // real fonts as CID-keyed/glyph-index-encoded content streams (not
  // simple ASCII-as-hex like the standard 14 fonts), so the rendered text
  // isn't recoverable by decompressing and hex-decoding the PDF's content
  // streams the way it is for the standard fonts; asserting glyph coverage
  // on the actual registered font files is the reliable way to guard this.
  const FONT_DIR = path.join(__dirname, "..", "src", "assets", "fonts");
  const DIACRITICS = ["č", "ć", "š", "đ", "ž", "Č", "Ć", "Š", "Đ", "Ž"];

  it.each(["IBMPlexSans-Variable.ttf", "IBMPlexMono-Regular.ttf", "IBMPlexMono-SemiBold.ttf"])(
    "%s has a glyph for every Serbian Latin diacritic",
    (filename) => {
      const font = fontkit.openSync(path.join(FONT_DIR, filename));
      const missing = DIACRITICS.filter((c) => !font.hasGlyphForCodePoint(c.codePointAt(0)));
      expect(missing).toEqual([]);
    }
  );
});

describe("GET /api/dev/reports and /api/dev/reports/:id/pdf (temporary, Phase 9)", () => {
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
    await Report.deleteMany({});
  });

  it("lists reports newest-first with id/status/plates", async () => {
    const older = await Report.create({ partyA: { vehicle: { plate: "OLD-1" } } });
    await new Promise((resolve) => setTimeout(resolve, 5));
    const newer = await Report.create({ partyA: { vehicle: { plate: "NEW-1" } } });

    const res = await request(app).get("/api/dev/reports");
    expect(res.status).toBe(200);
    const ids = res.body.map((r) => r._id);
    expect(ids.indexOf(newer._id.toString())).toBeLessThan(ids.indexOf(older._id.toString()));
    expect(res.body.find((r) => r._id === newer._id.toString()).partyAPlate).toBe("NEW-1");
  });

  it("streams a regenerated PDF for a given report id", async () => {
    const report = await Report.create({});
    const res = await request(app)
      .get(`/api/dev/reports/${report._id}/pdf`)
      .buffer(true)
      .parse((res, callback) => {
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => callback(null, Buffer.concat(chunks)));
      });

    expect(res.status).toBe(200);
    expect(res.headers["content-type"]).toBe("application/pdf");
    expect(isPdf(res.body)).toBe(true);
  });

  it("404s for an unknown report id", async () => {
    const res = await request(app).get(`/api/dev/reports/${new mongoose.Types.ObjectId()}/pdf`);
    expect(res.status).toBe(404);
  });
});
