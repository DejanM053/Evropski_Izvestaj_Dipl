const mongoose = require("mongoose");
const { STATUSES } = require("./statuses");

const WitnessSchema = new mongoose.Schema({ name: String, phone: String }, { _id: false });

const LocationSchema = new mongoose.Schema(
  { address: String, lat: Number, lng: Number },
  { _id: false }
);

const AccidentSchema = new mongoose.Schema(
  {
    dateTime: Date,
    location: { type: LocationSchema, default: () => ({}) },
    injuries: { type: Boolean, default: false },
    otherVehicleDamage: { type: Boolean, default: false },
    thirdPartyDamage: { type: Boolean, default: false },
    witnesses: { type: [WitnessSchema], default: [] },
  },
  { _id: false }
);

const DriverSchema = new mongoose.Schema(
  {
    firstName: String,
    lastName: String,
    address: String,
    phone: String,
    email: String,
    licenceNumber: String,
    licenceCategory: String,
    licenceValidUntil: Date,
  },
  { _id: false }
);

const VehicleSchema = new mongoose.Schema(
  { make: String, model: String, plate: String, country: String, vin: String },
  { _id: false }
);

const InsurerSchema = new mongoose.Schema(
  {
    company: String,
    policyNumber: String,
    greenCardNumber: String,
    validFrom: Date,
    validTo: Date,
    agency: String,
  },
  { _id: false }
);

const PolicyholderSchema = new mongoose.Schema(
  { name: String, address: String, phone: String },
  { _id: false }
);

const SignatureSchema = new mongoose.Schema(
  { fileId: { type: mongoose.Schema.Types.ObjectId, default: null }, signedAt: { type: Date, default: null } },
  { _id: false }
);

const PartyReportSchema = new mongoose.Schema(
  {
    driver: { type: DriverSchema, default: () => ({}) },
    vehicle: { type: VehicleSchema, default: () => ({}) },
    insurer: { type: InsurerSchema, default: () => ({}) },
    policyholder: { type: PolicyholderSchema, default: () => ({}) },
    circumstances: { type: [Number], default: [] },
    visibleDamage: { type: String, default: "" },
    remarks: { type: String, default: "" },
    signature: { type: SignatureSchema, default: () => ({}) },
    confirmedReview: { type: Boolean, default: false },
  },
  { _id: false }
);

const PhotoSchema = new mongoose.Schema(
  {
    fileId: mongoose.Schema.Types.ObjectId,
    caption: String,
    party: { type: String, enum: ["A", "B"] },
    takenAt: Date,
  },
  { _id: false }
);

const AttachmentHashSchema = new mongoose.Schema(
  {
    fileId: mongoose.Schema.Types.ObjectId,
    sha256: String,
    kind: String,
  },
  { _id: false }
);

const ChainSchema = new mongoose.Schema(
  {
    txHash: { type: String, default: null },
    blockNumber: { type: Number, default: null },
    contractAddress: { type: String, default: null },
    network: { type: String, default: null },
    anchoredAt: { type: Date, default: null },
    // §5.4 failure handling: if the anchor call fails, the report stays
    // "finalizing" (never silently sealed) and the error lands here so a
    // reconnecting client can render it without needing to have been
    // listening live for the report:progress broadcast. Cleared back to
    // null at the start of every finalize attempt (fresh or retry) and on
    // a successful anchor.
    lastError: { type: String, default: null },
  },
  { _id: false }
);

const ReportSchema = new mongoose.Schema({
  sessionId: { type: mongoose.Schema.Types.ObjectId, ref: "Session", default: null },
  status: { type: String, enum: STATUSES, default: "waiting" },
  // Phase 11 schema decision: §5.1 never defined where a client's locally
  // generated deviceId (mobile/lib/services/device_id_service.dart) lives,
  // so `GET /api/reports?deviceId=` was a no-op through Phase 10 (see
  // PROGRESS.md "Known scope gaps"). Recorded here rather than on Session
  // because History (§6 screen 15) scopes *reports*, not sessions, and a
  // session is TTL-reaped long before its report should disappear from
  // history. Both parties' deviceIds land in the same flat array (whichever
  // device created or joined the session, pushed once in
  // routes/sessions.js) — a report shows up in either party's history,
  // there's no need to know which slot a given device occupied.
  deviceIds: { type: [String], default: [] },
  accident: { type: AccidentSchema, default: () => ({}) },
  partyA: { type: PartyReportSchema, default: () => ({}) },
  partyB: { type: PartyReportSchema, default: () => ({}) },
  sketch: {
    fileId: { type: mongoose.Schema.Types.ObjectId, default: null },
  },
  photos: { type: [PhotoSchema], default: [] },
  pdf: {
    fileId: { type: mongoose.Schema.Types.ObjectId, default: null },
    sha256: { type: String, default: null },
    generatedAt: { type: Date, default: null },
  },
  attachmentHashes: { type: [AttachmentHashSchema], default: [] },
  bundleHash: { type: String, default: null },
  chain: { type: ChainSchema, default: () => ({}) },
  createdAt: { type: Date, default: Date.now },
  sealedAt: { type: Date, default: null },
});

module.exports = mongoose.model("Report", ReportSchema);
