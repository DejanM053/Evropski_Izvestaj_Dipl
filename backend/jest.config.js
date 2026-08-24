module.exports = {
  testEnvironment: "node",
  setupFiles: ["<rootDir>/test/setupEnv.js"],
  testTimeout: 20000,
  // Both test files reset the *same* real dockerized Mongo database in
  // their own beforeEach (PROGRESS.md's deliberate choice, Phase 3 — no
  // mongodb-memory-server, no per-file DB namespacing). Jest's default
  // parallel workers each open their own connection to that one database,
  // so one file's deleteMany/create can race and clobber the other file's
  // fixtures mid-test (discovered as an intermittent 404 on core routes
  // during Phase 7). Forcing one worker makes the two suites run serially.
  maxWorkers: 1,
};
