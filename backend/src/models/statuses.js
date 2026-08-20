const STATUSES = [
  "waiting",
  "joined",
  "filling",
  "review",
  "signing",
  "finalizing",
  "sealed",
  "abandoned",
];

// §5.3: "Reject all patches when status is signing or later."
const LOCKED_STATUSES = ["signing", "finalizing", "sealed", "abandoned"];

module.exports = { STATUSES, LOCKED_STATUSES };
