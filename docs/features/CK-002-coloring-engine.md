# CK-002 Coloring Engine

## Status
Implemented baseline, CK-002.1 foundation, CK-002.2 real SVG renderer, and CK-002.3 local multi-page catalog foundation.

## Goal
Provide a child-friendly tap-to-fill coloring experience that is easy to extend into a full content platform.

## Current Implementation
The coloring engine now uses a real SVG renderer for Happy Cat while preserving the repository -> controller/state -> canvas -> renderer architecture.

CK-002.3 extends this to multiple local Animals pages with stable category/page identity.

### Data Model
- `ColoringPage` contains:
  - `id`
  - `title`
  - `categoryId`
  - `assetPath`
  - `regions`
  - `sortOrder`
  - `rendererType`
- `ColoringRegion` contains:
  - `id`
  - `name`
  - `defaultColor`
- `ColoringState` contains:
  - `status` (loading, ready, error)
  - `page`
  - `regionColors`
  - `selectedColor`
  - `undoStack` (action-based)
  - `redoStack` (action-based)
  - `errorMessage`
- `ColoringHistoryAction` contains:
  - `regionId`
  - `previousColor`
  - `nextColor`

### Repository And Rendering Boundaries
- `ColoringPageRepository` abstracts page sources from controller logic.
- `ColoringPageRepository` owns category listing, page listing, category filtering, and page lookup.
- `LocalColoringPageRepository` currently returns a local in-memory multi-page catalog.
- `ColoringRenderer` defines rendering and region-validation contracts.
- `ColoringCanvas` validates renderer/page region IDs and fails gracefully on mismatch.
- `SvgColoringRenderer` loads, parses, validates, and renders SVG pages.
- `SvgColoringParser` parses colorable/static path elements and validates region-ID mapping.
- `SvgRegionHitTester` maps local taps to SVG viewBox coordinates and resolves regions in deterministic z-order.
- `HappyCatRenderer` remains available as a fallback renderer.

### Dependency Decisions
- Direct dependency on `xml` is used for SVG DOM parsing.
- Direct dependency on `path_drawing` is used for converting SVG path data into Flutter `Path` geometry.
- `flutter_svg` remains in the project for broader SVG ecosystem compatibility, while interaction and hit testing are implemented with public parsing/geometry APIs.

### Sample Content
- `sample_coloring_pages.dart` now defines a local Animals set:
  - Happy Cat
  - Playful Puppy
  - Friendly Lion
  - Cute Elephant

### Interaction Model
- The child selects a color from a 24-color palette.
- The child taps a region to fill it.
- Undo and redo are tracked as region-color actions.
- Clear resets the page.
- The canvas supports zooming and panning.
- SVG region hit testing is deterministic and based on rendered z-order.

### Offline Behavior
- The current implementation does not require an internet connection to operate once local assets are bundled in the app.

### CK-002.3 Catalog Behavior
- Home uses stable category IDs.
- Category catalog lists pages loaded by repository category query.
- Catalog item selection navigates to coloring with canonical page ID.
- Coloring sessions are intentionally in-memory and isolated to the active page session.

## Why This Baseline Exists
This prototype proves the core interaction model before the app expands into a large content library.

## Current SVG Asset Contract
- Each colorable region has a unique `id`.
- Colorable elements use `data-role="colorable"`.
- Static/non-colorable elements use `data-role="static"`.
- Optional labels may use `data-region-name`.
- Region IDs are canonical and must match `ColoringPage.regions` IDs.

## Next Planned Enhancement
Expand from local Animals coverage to broader local category coverage, then evaluate persistence and remote catalog phases.

Expected future behavior:
- Load SVG assets from local app content or cached storage.
- Map taps to named SVG regions through renderer implementations that satisfy the existing renderer contract.
- Keep undo/redo based on region-color state.
- Support export and recoloring more naturally.

## Non-Goals For This Baseline
- No full SVG parser is implemented yet.
- No Firebase-backed content loading is required for the first page.
- No brush tools are implemented yet.
- No AI generation is implemented yet.
