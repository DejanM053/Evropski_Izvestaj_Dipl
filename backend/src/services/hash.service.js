const crypto = require("crypto");

function sha256(buffer) {
  return crypto.createHash("sha256").update(buffer).digest("hex");
}

// §5.4 step 7: bundleHash = sha256(concat(sorted(attachmentHashes))).
//
// "Sorted" is not otherwise specified, so the deterministic order chosen
// here is: the attachments' own sha256 hex strings, sorted lexicographically
// ascending. This is independent of upload/insertion order (photos can land
// in either order depending on network timing between the two parties) and
// depends on nothing but the hash values themselves, so verify (§5.5) can
// recompute it later from a freshly-hashed attachment list without needing
// to know the original upload sequence. The sorted hex strings are then
// concatenated (as UTF-8 text, not raw bytes) and hashed once more.
function computeBundleHash(attachmentHashes) {
  const hexHashes = attachmentHashes.map((a) => (typeof a === "string" ? a : a.sha256));
  const sorted = [...hexHashes].sort();
  return sha256(Buffer.from(sorted.join(""), "utf8"));
}

module.exports = { sha256, computeBundleHash };
