# ADR-004: Local Coloring Session Persistence

## Status
Accepted and implemented in CK-002.4.

## Context
CK-002.3 delivered a stable local multi-page SVG coloring flow with deterministic category/page identity, but coloring progress was in-memory only. Users lost progress when leaving a page or restarting the app.

The product needed a small, reliable, offline-friendly way to resume in-progress coloring without changing the existing catalog, routing, or renderer architecture.

## Decision
Introduce a dedicated persistence boundary for user-created coloring progress:

- Keep `ColoringPageRepository` focused on content and catalog data.
- Add `ColoringSessionRepository` for local session persistence.
- Implement local storage using SharedPreferences.
- Persist sessions per stable `pageId` key namespace:
  - `coloring_session:<pageId>`

Session model:
- `pageId`
- `regionColors` as ARGB integers (`Map<String, int>`)
- `schemaVersion` (current: `1`)
- `lastUpdatedAtEpochMs`

Restore behavior:
- load page content
- build defaults
- load session by page ID
- apply saved colors only for known region IDs
- ignore unknown region IDs
- keep defaults for newly added regions
- start with empty undo/redo stacks

Save behavior:
- persist after fill, undo, and redo
- clear resets visible colors and deletes persisted session
- persistence is asynchronous and serialized to avoid stale write ordering

Session listing behavior (`getAllSessions`):
- enumerate only keys in the `coloring_session:` namespace
- parse entries independently so one malformed payload does not block others
- exclude malformed entries
- exclude unsupported schema entries
- return deterministic ordering:
  - newest `lastUpdatedAtEpochMs` first
  - then `pageId` ascending for timestamp ties

## Alternatives Considered

### SharedPreferences
- Chosen for CK-002.4.
- Low implementation complexity.
- Sufficient for current session payload size.
- Available across target platforms.

### Local JSON Files (`path_provider` + `dart:io`)
- Flexible but introduces more file-management complexity.
- Less attractive for web compatibility and MVP speed.

### Local Database (Hive/Isar/SQLite)
- More scalable but unnecessary complexity for current data size and requirements.

## Consequences
- Coloring progress now survives page navigation and app/controller recreation.
- Page sessions remain isolated by stable page IDs.
- Existing rendering and catalog architecture remains unchanged.
- Undo/redo history is intentionally not persisted.
- SharedPreferences can be replaced later behind `ColoringSessionRepository` without touching controller logic.
- My Creations can compose started-page resume cards directly from persisted sessions and catalog metadata without embedding persistence logic in UI widgets.

## Failure Semantics
- Persistence is non-fatal to coloring interactions.
- If session read fails, malformed JSON is found, or schema is unsupported:
  - ignore persisted payload
  - fall back to default in-memory coloring state
- For `getAllSessions`, malformed/unsupported entries are skipped while remaining valid sessions still load.
- If save/delete fails:
  - keep current in-memory coloring usable
  - do not surface a child-facing fatal error screen
- Content load failures remain part of existing fatal loading/error behavior.

## Versioning Strategy
- `schemaVersion = 1` introduced at first persistence release.
- Unsupported schema versions are safely ignored.
- Region reconciliation is ID-based, which tolerates additive/removal changes without a migration framework.

## Future Cloud Migration Considerations
- Keep `ColoringSessionRepository` API storage-agnostic.
- Future cloud sync can add a remote implementation and conflict policy without changing renderer or catalog repositories.
- Stable `pageId` identity remains the canonical merge key for page progress.
