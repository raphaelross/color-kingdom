# CK-002 Coloring Engine

## Status
Implemented baseline plus CK-002.1 production foundation, with a planned enhancement path toward SVG-based named-region assets.

## Goal
Provide a child-friendly tap-to-fill coloring experience that is easy to extend into a full content platform.

## Current Implementation
The current coloring engine remains a prototype renderer for a single sample page, but now uses repository and renderer boundaries intended for production evolution.

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
- `HappyCatRenderer` provides the current concrete sample renderer.

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

### Offline Behavior
- The current implementation does not require an internet connection to operate once the sample page is available in the app.

## Why This Baseline Exists
This prototype proves the core interaction model before the app expands into a large content library.

## Next Planned Enhancement
Replace the placeholder sample renderer with a real SVG + named-region asset pipeline.

Expected future behavior:
- Load SVG assets from local app content or cached storage.
- Map taps to named SVG regions through a renderer implementation that satisfies the existing renderer contract.
- Keep undo/redo based on region-color state.
- Support export and recoloring more naturally.

## Non-Goals For This Baseline
- No full SVG parser is implemented yet.
- No Firebase-backed content loading is required for the first page.
- No brush tools are implemented yet.
- No AI generation is implemented yet.
