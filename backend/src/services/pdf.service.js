const path = require("path");
const PDFDocument = require("pdfkit");
const storage = require("./storage.service");
const { CIRCUMSTANCES } = require("../constants/circumstances");

// §5.6: layout mirrors the European Accident Statement — header, two party
// columns, circumstances grid, damage/remarks, witnesses, sketch, photo
// appendix, signatures, footer — in that order. No chain data (contract
// address, network, tx hash) appears anywhere in this document — see
// stampFooterOnAllPages's comment for why. Nothing in this file calls the
// chain (no RPC, no ethers) — Phase 9 is generation only.

const PAGE_MARGINS = { top: 40, bottom: 55, left: 40, right: 40 };

// pdfkit's standard 14 fonts (Helvetica, Courier, ...) only support
// WinAnsiEncoding (Windows-1252) — which has š/Š and ž/Ž, but has no code
// points for č/ć/đ/Č/Ć/Đ at all. Text using those (any word with "č", "ć",
// or "đ" — extremely common in Serbian) silently dropped the character or
// rendered the wrong glyph. Fixed by embedding real fonts instead, reusing
// the exact IBM Plex files already bundled for the Flutter app
// (mobile/assets/fonts/, chosen there for the same reason — see
// .claude/rules/mobile.md) rather than adding a new font dependency; a
// `fontkit`-based coverage check against all five diacritics confirmed
// full glyph coverage before wiring this up. Only Regular + one SemiBold
// (both real static weight files, unlike IBM Plex Sans's variable-font
// download, which pdfkit/fontkit can only render at its default instance)
// were pulled in — enough to cover this document's two roles (prose vs.
// section headings/labels/data), not the whole four-family app type scale.
const FONT_DIR = path.join(__dirname, "..", "assets", "fonts");

function registerFonts(doc) {
  doc.registerFont("Sans", path.join(FONT_DIR, "IBMPlexSans-Variable.ttf"));
  doc.registerFont("Mono", path.join(FONT_DIR, "IBMPlexMono-Regular.ttf"));
  doc.registerFont("Mono-SemiBold", path.join(FONT_DIR, "IBMPlexMono-SemiBold.ttf"));
}

function contentWidth(doc) {
  return doc.page.width - doc.page.margins.left - doc.page.margins.right;
}

function ensureSpace(doc, height) {
  if (doc.y + height > doc.page.height - doc.page.margins.bottom) {
    doc.addPage();
  }
}

function dash(value) {
  if (value === null || value === undefined) return "—";
  const s = String(value).trim();
  return s.length > 0 ? s : "—";
}

function pad2(n) {
  return String(n).padStart(2, "0");
}

function fmtDateTime(d) {
  if (!d) return "—";
  const dt = new Date(d);
  if (Number.isNaN(dt.getTime())) return "—";
  return `${pad2(dt.getDate())}.${pad2(dt.getMonth() + 1)}.${dt.getFullYear()}. ${pad2(dt.getHours())}:${pad2(dt.getMinutes())}`;
}

function fmtDateOnly(d) {
  if (!d) return "—";
  const dt = new Date(d);
  if (Number.isNaN(dt.getTime())) return "—";
  return `${pad2(dt.getDate())}.${pad2(dt.getMonth() + 1)}.${dt.getFullYear()}.`;
}

function fmtDateRange(a, b) {
  if (!a && !b) return "—";
  return `${fmtDateOnly(a)} – ${fmtDateOnly(b)}`;
}

async function safeFetchBuffer(fileId) {
  if (!fileId) return null;
  try {
    return await storage.getFileBuffer(fileId);
  } catch (err) {
    // A missing/orphaned GridFS file shouldn't fail the whole PDF —
    // rendered as an explicit "not available" placeholder instead (§9.4:
    // "handle the awkward cases").
    return null;
  }
}

function sectionHeading(doc, text) {
  doc.moveDown(0.4);
  ensureSpace(doc, 26);
  doc.font("Mono-SemiBold").fontSize(11).fillColor("#12274A").text(text.toUpperCase());
  const y = doc.y + 2;
  doc
    .moveTo(doc.page.margins.left, y)
    .lineTo(doc.page.margins.left + contentWidth(doc), y)
    .strokeColor("#CFCABD")
    .lineWidth(1)
    .stroke();
  doc.fillColor("#000000");
  doc.y = y + 8;
  doc.x = doc.page.margins.left;
}

// --- Header ------------------------------------------------------------

function drawHeader(doc, report) {
  doc.font("Mono-SemiBold").fontSize(17).fillColor("#12274A");
  doc.text("EVROPSKI IZVEŠTAJ O SAOBRAĆAJNOJ NEZGODI", { align: "center" });
  doc.fillColor("#000000");
  doc.moveDown(0.15);
  doc.font("Sans").fontSize(8.5).fillColor("#5C6270");
  doc.text(`Broj izveštaja: ${report._id}`, { align: "center" });
  doc.fillColor("#000000");
  doc.moveDown(0.6);

  const width = contentWidth(doc);
  doc.font("Mono-SemiBold").fontSize(9).text("Vreme i mesto nezgode", { width });
  doc.font("Sans").fontSize(9);
  doc.text(`Datum i vreme: ${fmtDateTime(report.accident?.dateTime)}`, { width });

  const loc = report.accident?.location || {};
  const coords =
    loc.lat !== null && loc.lat !== undefined && loc.lng !== null && loc.lng !== undefined
      ? ` (${Number(loc.lat).toFixed(5)}, ${Number(loc.lng).toFixed(5)})`
      : "";
  doc.text(`Mesto: ${dash(loc.address)}${coords}`, { width });

  const flags = [];
  if (report.accident?.injuries) flags.push("ima povređenih");
  if (report.accident?.otherVehicleDamage) flags.push("oštećena druga vozila");
  if (report.accident?.thirdPartyDamage) flags.push("oštećena imovina trećih lica");
  doc.text(`Napomene o posledicama: ${flags.length ? flags.join(", ") : "nema prijavljenih posledica"}`, { width });

  doc.moveDown(0.3);
}

// --- Party columns (driver / vehicle / insurer / policyholder) --------

function partyRows(party) {
  const d = party?.driver || {};
  const v = party?.vehicle || {};
  const ins = party?.insurer || {};
  const p = party?.policyholder || {};

  const rows = [
    ["Vozač", [d.firstName, d.lastName].filter(Boolean).join(" ")],
    ["Adresa", d.address],
    ["Telefon", d.phone],
    ["E-mail", d.email],
    ["Br. vozačke", d.licenceNumber],
    ["Kategorija", d.licenceCategory],
    ["Vozačka važi do", fmtDateOnly(d.licenceValidUntil)],
    ["Vozilo", [v.make, v.model].filter(Boolean).join(" ")],
    ["Reg. tablica", v.plate],
    ["Država", v.country],
    ["Broj šasije (VIN)", v.vin],
    ["Osiguravač", ins.company],
    ["Broj polise", ins.policyNumber],
    ["Broj zel. karte", ins.greenCardNumber],
    ["Polisa važi", fmtDateRange(ins.validFrom, ins.validTo)],
    ["Agencija", ins.agency],
  ];

  if (p.name || p.address || p.phone) {
    rows.push(["Vlasnik polise", p.name]);
    if (p.address) rows.push(["  — adresa", p.address]);
    if (p.phone) rows.push(["  — telefon", p.phone]);
  }

  return rows;
}

function drawTwoColumnRows(doc, leftRows, rightRows) {
  const width = contentWidth(doc);
  const gap = 20;
  const colWidth = (width - gap) / 2;
  const labelWidth = 82;
  const valueWidth = colWidth - labelWidth - 4;
  const rowHeight = 12.5;
  const startX = doc.page.margins.left;
  const maxRows = Math.max(leftRows.length, rightRows.length);

  // The field set is fixed-size and modest (~16-19 rows), so rather than
  // let a grid split awkwardly across a page boundary mid-row, just start
  // a fresh page up front if the whole thing won't fit where we are.
  ensureSpace(doc, maxRows * rowHeight + 10);
  const y0 = doc.y;

  function drawColumn(rows, x) {
    rows.forEach(([label, rawValue], i) => {
      const y = y0 + i * rowHeight;
      doc
        .font("Mono-SemiBold")
        .fontSize(7)
        .fillColor("#5C6270")
        .text(label.toUpperCase(), x, y, { width: labelWidth, lineBreak: false });
      doc
        .font("Sans")
        .fontSize(8.5)
        .fillColor("#000000")
        .text(dash(rawValue), x + labelWidth, y, {
          width: valueWidth,
          height: rowHeight,
          ellipsis: true,
          lineBreak: false,
        });
    });
  }

  drawColumn(leftRows, startX);
  drawColumn(rightRows, startX + colWidth + gap);

  doc.x = startX;
  doc.y = y0 + maxRows * rowHeight + 6;
}

function drawPartyColumns(doc, report) {
  sectionHeading(doc, "Strane u nezgodi");

  const width = contentWidth(doc);
  const gap = 20;
  const colWidth = (width - gap) / 2;
  const startX = doc.page.margins.left;
  const headingY = doc.y;

  doc.font("Mono-SemiBold").fontSize(9.5).fillColor("#12274A");
  doc.text("STRANA A", startX, headingY, { width: colWidth });
  doc.text("STRANA B", startX + colWidth + gap, headingY, { width: colWidth });
  doc.fillColor("#000000");
  doc.y = headingY + 14;
  doc.x = startX;

  drawTwoColumnRows(doc, partyRows(report.partyA), partyRows(report.partyB));
}

// --- Circumstances grid --------------------------------------------------

function drawCheckRow(doc, x, y, boxSize, textWidth, label, checked) {
  doc.rect(x, y + 1, boxSize, boxSize).lineWidth(0.75).strokeColor("#333333").stroke();
  if (checked) {
    doc
      .moveTo(x + 1.5, y + 1 + boxSize / 2)
      .lineTo(x + boxSize / 2, y + boxSize - 0.5)
      .lineTo(x + boxSize - 0.5, y + 1.5)
      .strokeColor("#000000")
      .lineWidth(1.2)
      .stroke();
  }
  doc
    .font(checked ? "Mono-SemiBold" : "Sans")
    .fontSize(8)
    .fillColor("#000000")
    .text(label, x + boxSize + 6, y, { width: textWidth });
}

function drawCircumstancesGrid(doc, report) {
  sectionHeading(doc, "Okolnosti nezgode");

  const width = contentWidth(doc);
  const gap = 20;
  const boxSize = 8;
  const colWidth = (width - gap) / 2;
  const textWidth = colWidth - boxSize - 6;
  const startX = doc.page.margins.left;

  const aSet = new Set(report.partyA?.circumstances || []);
  const bSet = new Set(report.partyB?.circumstances || []);

  doc.font("Sans").fontSize(8);
  const rowHeights = CIRCUMSTANCES.map((label) =>
    Math.max(boxSize + 3, doc.heightOfString(label, { width: textWidth }))
  );
  const totalHeight = rowHeights.reduce((sum, h) => sum + h + 3, 0);

  ensureSpace(doc, totalHeight + 20);
  let y = doc.y;

  CIRCUMSTANCES.forEach((label, i) => {
    drawCheckRow(doc, startX, y, boxSize, textWidth, label, aSet.has(i));
    drawCheckRow(doc, startX + colWidth + gap, y, boxSize, textWidth, label, bSet.has(i));
    y += rowHeights[i] + 3;
  });

  doc.x = startX;
  doc.y = y + 4;
  doc
    .font("Mono-SemiBold")
    .fontSize(8.5)
    .text(`Strana A: ${aSet.size} označeno      Strana B: ${bSet.size} označeno`, startX, doc.y);
  doc.moveDown(0.4);
}

// --- Damage / remarks / witnesses (free text — left to pdfkit's own
// wrap+auto-paginate, unlike the fixed-row grids above, since these are
// user-typed and can be arbitrarily long) --------------------------------

function drawFreeText(doc, heading, text) {
  const width = contentWidth(doc);
  doc.font("Mono-SemiBold").fontSize(8.5).text(heading, { width });
  doc.font("Sans").fontSize(8.5).text(dash(text), { width });
  doc.moveDown(0.3);
}

function drawDamageAndRemarks(doc, report) {
  sectionHeading(doc, "Vidljiva oštećenja i napomene");
  drawFreeText(doc, "Strana A — vidljiva oštećenja", report.partyA?.visibleDamage);
  drawFreeText(doc, "Strana A — napomene", report.partyA?.remarks);
  drawFreeText(doc, "Strana B — vidljiva oštećenja", report.partyB?.visibleDamage);
  drawFreeText(doc, "Strana B — napomene", report.partyB?.remarks);
}

function drawWitnesses(doc, report) {
  sectionHeading(doc, "Svedoci");
  const width = contentWidth(doc);
  const witnesses = report.accident?.witnesses || [];
  doc.font("Sans").fontSize(9);
  if (witnesses.length === 0) {
    doc.text("Nema prijavljenih svedoka.", { width });
  } else {
    witnesses.forEach((w) => {
      doc.text(`• ${dash(w.name)} — ${dash(w.phone)}`, { width });
    });
  }
  doc.moveDown(0.3);
}

// --- Sketch --------------------------------------------------------------

function drawSketch(doc, sketchBuffer) {
  sectionHeading(doc, "Skica nezgode");
  const width = contentWidth(doc);

  if (!sketchBuffer) {
    doc.font("Sans").fontSize(9).text("Skica nije dodata.", { width });
    doc.moveDown(0.3);
    return;
  }

  const maxH = 260;
  ensureSpace(doc, maxH + 10);
  const x = doc.page.margins.left;
  const y = doc.y;
  try {
    doc.image(sketchBuffer, x, y, { fit: [width, maxH], align: "center", valign: "center" });
  } catch (err) {
    doc.font("Sans").fontSize(8.5).fillColor("#A6322A").text(`Skica nije prikazana (${err.message}).`, x, y, { width });
    doc.fillColor("#000000");
  }
  doc.x = x;
  doc.y = y + maxH + 10;
}

// --- Photo appendix (2 per row, paginates automatically as rows run out
// of vertical space — §9.4's "photo appendix spanning multiple pages") --

function drawPhotoAppendix(doc, report, photoBuffers) {
  sectionHeading(doc, "Prilog: fotografije");
  const width = contentWidth(doc);
  const photos = report.photos || [];

  if (photos.length === 0) {
    doc.font("Sans").fontSize(9).text("Nema priloženih fotografija.", { width });
    doc.moveDown(0.3);
    return;
  }

  const gap = 20;
  const cellW = (width - gap) / 2;
  const imgH = 170;
  const captionH = 22;
  const cellH = imgH + captionH;
  const startX = doc.page.margins.left;

  let col = 0;
  let rowY = doc.y;

  photos.forEach((photo, idx) => {
    if (col === 0 && rowY + cellH > doc.page.height - doc.page.margins.bottom) {
      doc.addPage();
      rowY = doc.y;
    }

    const x = startX + col * (cellW + gap);
    const buffer = photoBuffers[idx];
    if (buffer) {
      try {
        doc.image(buffer, x, rowY, { fit: [cellW, imgH], align: "center", valign: "center" });
      } catch (err) {
        doc
          .font("Sans")
          .fontSize(7.5)
          .fillColor("#A6322A")
          .text("(fotografija nije prikazana)", x, rowY + imgH / 2 - 5, { width: cellW, align: "center" });
        doc.fillColor("#000000");
      }
    } else {
      doc
        .font("Sans")
        .fontSize(7.5)
        .fillColor("#A6322A")
        .text("(fotografija nedostupna)", x, rowY + imgH / 2 - 5, { width: cellW, align: "center" });
      doc.fillColor("#000000");
    }

    const captionText = `${photo.party ? `Strana ${photo.party} · ` : ""}${dash(photo.caption)}`;
    doc
      .font("Sans")
      .fontSize(7.5)
      .fillColor("#3A3F49")
      .text(captionText, x, rowY + imgH + 3, { width: cellW, height: captionH - 3, ellipsis: true });
    doc.fillColor("#000000");

    col += 1;
    if (col === 2) {
      col = 0;
      rowY += cellH + 10;
    }
  });

  doc.x = startX;
  doc.y = col === 0 ? rowY : rowY + cellH + 10;
  doc.moveDown(0.2);
}

// --- Signatures ------------------------------------------------------------

function drawSignatures(doc, report, sigBufferA, sigBufferB) {
  sectionHeading(doc, "Potpisi");
  const width = contentWidth(doc);
  const gap = 20;
  const colWidth = (width - gap) / 2;
  const imgH = 100;

  ensureSpace(doc, imgH + 42);
  const startX = doc.page.margins.left;
  const y = doc.y;

  function drawOne(x, label, buffer, signedAt) {
    doc.font("Mono-SemiBold").fontSize(9).fillColor("#12274A").text(label, x, y, { width: colWidth });
    doc.fillColor("#000000");
    const boxY = y + 14;
    doc.rect(x, boxY, colWidth, imgH).strokeColor("#CFCABD").lineWidth(0.75).stroke();
    if (buffer) {
      try {
        doc.image(buffer, x + 4, boxY + 4, { fit: [colWidth - 8, imgH - 8], align: "center", valign: "center" });
      } catch (err) {
        doc
          .font("Sans")
          .fontSize(8.5)
          .fillColor("#A6322A")
          .text("(potpis nije prikazan)", x, boxY + imgH / 2 - 5, { width: colWidth, align: "center" });
        doc.fillColor("#000000");
      }
    } else {
      doc
        .font("Sans")
        .fontSize(8.5)
        .fillColor("#A6322A")
        .text("Potpis nije dostupan", x, boxY + imgH / 2 - 5, { width: colWidth, align: "center" });
      doc.fillColor("#000000");
    }
    doc
      .font("Sans")
      .fontSize(7.5)
      .fillColor("#5C6270")
      .text(`Potpisano: ${fmtDateTime(signedAt)}`, x, boxY + imgH + 4, { width: colWidth });
    doc.fillColor("#000000");
  }

  drawOne(startX, "Strana A", sigBufferA, report.partyA?.signature?.signedAt);
  drawOne(startX + colWidth + gap, "Strana B", sigBufferB, report.partyB?.signature?.signedAt);

  doc.x = startX;
  doc.y = y + 14 + imgH + 22;
}

// --- Footer (every page) --------------------------------------------------

// Deliberately minimal: report ID, PDF SHA-256, contract address, and
// network are all already shown in the app's own report history/detail
// views (or, for contract address/network, only become meaningful once
// Phase 10 actually anchors this specific report — printing the address
// here beforehand just looked like orphaned noise with nothing tying it to
// this document). Page number is the only thing left, since it's genuinely
// about navigating a multi-page PDF, not chain metadata.
//
// No on-chain data of any kind appears in this document, which is also
// exactly right per §5.6's ordering note for the strongest case of the
// three (tx hash): finalize (§5.4) generates and hashes the PDF (steps 3-4)
// *before* it ever calls anchor() (step 9), so the tx hash literally
// doesn't exist yet at the moment this file runs and could never be
// embedded in the very document whose hash gets anchored, regardless of
// how the footer is styled. It's shown in-app and on the verify screen
// (§5.5) instead, never here.
function stampFooterOnAllPages(doc) {
  const range = doc.bufferedPageRange();
  const width = contentWidth(doc);

  for (let i = range.start; i < range.start + range.count; i++) {
    doc.switchToPage(i);

    // pdfkit's text engine auto-inserts a page break whenever a line's y
    // would land past `page.height - page.margins.bottom` — it has no way
    // to know we're *deliberately* drawing inside that reserved strip for
    // the footer itself. Left alone, that silently appended a fresh blank
    // page after every single page in the document (the exact "excess
    // empty pages" bug this comment replaced). Zeroing the bottom margin
    // just for this draw call defuses that check; nothing else on this
    // page is drawn after it, so there's no real content left to protect
    // from encroaching into the margin.
    const savedBottomMargin = doc.page.margins.bottom;
    doc.page.margins.bottom = 0;

    const y = doc.page.height - savedBottomMargin + 18;
    doc
      .font("Mono")
      .fontSize(6.5)
      .fillColor("#5C6270")
      .text(`${i - range.start + 1} / ${range.count}`, doc.page.margins.left, y, {
        width,
        align: "right",
        lineBreak: false,
      });
    doc.fillColor("#000000");

    doc.page.margins.bottom = savedBottomMargin;
  }
}

// --- Document assembly ----------------------------------------------------

function buildDocument(report, assets) {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: "A4", margins: PAGE_MARGINS, bufferPages: true });
    registerFonts(doc);
    const chunks = [];
    doc.on("data", (chunk) => chunks.push(chunk));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);

    try {
      drawHeader(doc, report);
      drawPartyColumns(doc, report);
      drawCircumstancesGrid(doc, report);
      drawDamageAndRemarks(doc, report);
      drawWitnesses(doc, report);
      drawSketch(doc, assets.sketchBuffer);
      drawPhotoAppendix(doc, report, assets.photoBuffers);
      drawSignatures(doc, report, assets.sigABuffer, assets.sigBBuffer);
      stampFooterOnAllPages(doc);
      doc.end();
    } catch (err) {
      reject(err);
    }
  });
}

// Generates the full report PDF (§5.6) as a Buffer. `report` is a Report
// document (or plain object with the same shape) — this function only
// reads it and fetches its attachments from GridFS; it never mutates or
// saves it, and never touches the chain. Single pass — nothing in the
// document depends on the document's own output, so there's no ordering
// problem left to solve here (see stampFooterOnAllPages's comment for the
// one piece of chain data that's still deliberately excluded, and why).
async function generateReportPdf(report) {
  const [sketchBuffer, sigABuffer, sigBBuffer, photoBuffers] = await Promise.all([
    safeFetchBuffer(report.sketch?.fileId),
    safeFetchBuffer(report.partyA?.signature?.fileId),
    safeFetchBuffer(report.partyB?.signature?.fileId),
    Promise.all((report.photos || []).map((p) => safeFetchBuffer(p.fileId))),
  ]);
  const assets = { sketchBuffer, sigABuffer, sigBBuffer, photoBuffers };

  return buildDocument(report, assets);
}

module.exports = { generateReportPdf };
