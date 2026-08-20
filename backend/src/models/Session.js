const mongoose = require("mongoose");
const { STATUSES } = require("./statuses");

const PartySchema = new mongoose.Schema(
  {
    socketId: { type: String, default: null },
    joinedAt: { type: Date, default: null },
    ready: { type: Boolean, default: false },
  },
  { _id: false }
);

const SessionSchema = new mongoose.Schema({
  sessionCode: { type: String, required: true, uppercase: true, index: true },
  status: { type: String, enum: STATUSES, default: "waiting" },
  partyA: { type: PartySchema, default: () => ({}) },
  partyB: { type: PartySchema, default: () => ({}) },
  reportId: { type: mongoose.Schema.Types.ObjectId, ref: "Report" },
  createdAt: { type: Date, default: Date.now },
  expiresAt: { type: Date, required: true },
});

// TTL index: Mongo reaps the document once expiresAt is in the past.
SessionSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

module.exports = mongoose.model("Session", SessionSchema);
