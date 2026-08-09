# CK-002 Coloring Engine

## Status
Implemented baseline, CK-002.1 foundation, and CK-002.2 real SVG renderer for Happy Cat.

## Goal
Provide a child-friendly tap-to-fill coloring experience that is easy to extend into a full content platform.

## Current Implementation
The coloring engine now uses a real SVG renderer for Happy Cat while preserving the repository -> controller/state -> canvas -> renderer architecture.

### Data Model
- `ColoringPage` contains:
  - `id`
  - `title`
  - `category`
  - `assetPath`
  - `regions`
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
- `LocalColoringPageRepository` currently returns the sample Happy Cat page in memory.
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
- `sample_coloring_pages.dart` currently defines a single sample page:
  - Happy Cat
- The sample cat includes named regions for:
  - Body
  - Head
  - Left Ear
  - Right Ear
  - Left Eye
  - Right Eye
  - Nose
  - Collar
  - Tail

### Interaction Model
- The child selects a color from a 24-color palette.
- The child taps a region to fill it.
- Undo and redo are tracked as region-color actions.
- Clear resets the page.
- The canvas supports zooming and panning.
- SVG region hit testing is deterministic and based on rendered z-order.

### Offline Behavior
- The current implementation does not require an internet connection to operate once the sample page is available in the app.

## Why This Baseline Exists
This prototype proves the core interaction model before the app expands into a large content library.

## Current SVG Asset Contract
- Each colorable region has a unique `id`.
- Colorable elements use `data-role="colorable"`.
- Static/non-colorable elements use `data-role="static"`.
- Optional labels may use `data-region-name`.
- Region IDs are canonical and must match `ColoringPage.regions` IDs.

## Next Planned Enhancement
Expand from one SVG page to a larger validated SVG content library with repository-backed sources.

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
