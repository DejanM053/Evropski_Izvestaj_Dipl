// Serializes async work per report so concurrent writes to the same report
// can't race each other's fetch-modify-save cycle. Found via a live report
// where `partyA.vehicle` ended up missing entirely and `partyA.insurer` had
// only its last-patched field, after the mobile app's "fill sample data"
// button fired ~18 `report:patch` messages back-to-back with no pacing
// (see `session.socket.js`'s `report:patch` handler, the one caller today).
//
// Root cause: each `report:patch` handler invocation does its own fresh
// `Report.findById` → `.set(path, value)` → `.save()`. When several patches
// for the same report are in flight at once, each fetches a snapshot before
// any of the others have committed. For a leaf under a *not-yet-existing*
// nested subdocument (e.g. `partyA.vehicle.make` when `partyA.vehicle`
// doesn't exist yet), Mongoose's dirty-path tracking marks the whole parent
// path — not the individual leaf — as modified, so each concurrent patch's
// `.save()` generates a conflicting `$set` of the *entire* parent object.
// Concurrent whole-object `$set`s to the same key don't merge; whichever
// commits last silently wins and discards the others' fields, with no
// error anywhere — reproduced reliably (first try, not a rare flake) with
// a standalone script mimicking the exact burst pattern.
//
// A plain in-memory Map of promise chains, one per reportId, fixes this by
// making the whole fetch→set→save→broadcast sequence run to completion for
// one patch before the next one (for the *same* report) starts — single
// Node process (no clustering per docker-compose §7), so this fully
// serializes same-report work without needing a distributed lock. Patches
// for *different* reports still run fully concurrently; nothing here
// changes per-patch latency for the common case of one patch at a time.
const _queues = new Map();

/// Runs `task` after every previously queued task for `reportId` has
/// settled, and returns `task`'s own result/rejection to the caller
/// unchanged. A failing task never wedges the queue for later tasks on the
/// same report — the map's stored chain tail always resolves, regardless
/// of whether the task it followed succeeded.
function withReportLock(reportId, task) {
  const key = String(reportId);
  const previous = _queues.get(key) || Promise.resolve();
  const next = previous.then(task, task);
  _queues.set(
    key,
    next.then(
      () => {},
      () => {}
    )
  );
  return next;
}

module.exports = { withReportLock };
