const crypto = require("crypto");
const Session = require("../models/Session");

// Excludes 0/O and 1/I/L — visually ambiguous in a 6-char human-read-aloud code.
const ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
const CODE_LENGTH = 6;
const MAX_ATTEMPTS = 10;

function randomCode() {
  let code = "";
  for (let i = 0; i < CODE_LENGTH; i++) {
    code += ALPHABET[crypto.randomInt(ALPHABET.length)];
  }
  return code;
}

async function generateUniqueSessionCode() {
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const code = randomCode();
    const existing = await Session.findOne({
      sessionCode: code,
      expiresAt: { $gt: new Date() },
    });
    if (!existing) return code;
  }
  throw new Error(`failed to generate a unique session code after ${MAX_ATTEMPTS} attempts`);
}

module.exports = { generateUniqueSessionCode, ALPHABET, CODE_LENGTH };
