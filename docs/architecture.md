# Architecture

## Architecture Summary
Color Kingdom currently uses a feature-first Flutter architecture with a shared app shell, centralized routing, a global theme, and feature-local state management for coloring.

CK-002.4 adds local save-and-resume coloring progress while preserving the existing CK-002.1/CK-002.2/CK-002.3 boundaries.

CK-002.5 adds a child-facing My Creations surface that composes existing page metadata and persisted sessions without changing the coloring engine architecture.

CK-002.6 Phase 1 adds a polished SVG authoring standard, reusable SVG content validation, and the Lovely Kitten benchmark page without redesigning renderer architecture.

CK-002.6 Phase 2E adds a runtime raster-region renderer proof of concept for Lovely Kitten while preserving the existing SVG implementation.

## Implemented Architecture Today

### App Shell
- `lib/main.dart` starts the app.
- `lib/app/app.dart` hosts `MaterialApp.router`.
- `lib/app/theme/` contains the global theme system.
- `lib/app/router/app_router.dart` defines the route table.

### Navigation
- Navigation is managed through named `go_router` routes.
- The root route opens the splash screen.
- Splash transitions to Home automatically.
- Home routes into category catalogs, gallery, and parent zone.
- Category navigation uses stable category IDs in `/category/:categoryId`.
- Coloring navigation uses stable page IDs in `/coloring/:pageId`.

### Feature Structure
- `lib/features/home/` owns the home experience and reusable category card widget.
- `lib/features/coloring/` owns the current coloring baseline.
- `lib/features/categories/` now owns category identity models and the page catalog screen.
- `lib/features/gallery/` now owns My Creations presentation and provider-based composition.
- `parent/` and `settings/` remain non-coloring sections.
- `lib/shared/` exists for future reusable widgets and providers.

### Category And Catalog Foundation (CK-002.3)
- Category identity is data-driven with stable IDs.
- Categories expose only:
	- `categoryId`
	- `title`
	- `sortOrder`
	- optional `emoji`
- `ColoringPageRepository` owns category and page catalog responsibilities:
	- category listing
	- page listing
	- page filtering by category
	- deterministic ordering
	- page lookup by ID
- `CategoryScreen` is a catalog view that consumes repository-backed providers.

### Coloring Engine Baseline
The current coloring implementation now uses a production-ready renderer-independent foundation with an SVG renderer for Happy Cat.

Current coloring pieces:
- `models/coloring_page.dart` defines `ColoringPage` and `ColoringRegion`.
- `models/coloring_state.dart` defines loading/ready/error state plus action-based undo/redo history entries.
- `data/sample_coloring_pages.dart` defines multiple local Animals pages.
- `repositories/coloring_page_repository.dart` defines the page-source abstraction.
- `repositories/local_coloring_page_repository.dart` provides the current in-memory local catalog source.
- `repositories/coloring_session_repository.dart` defines the local user-progress persistence abstraction.
- `repositories/local_coloring_session_repository.dart` provides a SharedPreferences-backed local session implementation.
- `providers/coloring_provider.dart` manages loading state, selected color, fills, undo, redo, clear, and page selection.
- `screens/coloring_screen.dart` composes toolbar, canvas, and palette.
- `widgets/coloring_renderer.dart` defines the renderer contract and region validation.
- `widgets/coloring_renderer_registry.dart` resolves a renderer by renderer type metadata.
- `widgets/coloring_canvas.dart` hosts zoom/pan, runs renderer/page validation, and delegates drawing to a renderer.
- `widgets/renderers/svg/svg_coloring_renderer.dart` loads, validates, caches, and renders SVG coloring pages.
- `widgets/renderers/svg/svg_coloring_parser.dart` parses SVG assets and validates colorable region IDs.
- `widgets/renderers/svg/svg_content_validator.dart` performs reusable deterministic SVG content contract validation and warning diagnostics.
- `widgets/renderers/svg/svg_region_hit_tester.dart` maps taps into SVG coordinates and resolves region hits.
- `widgets/renderers/svg/svg_coloring_models.dart` contains SVG renderer-specific internal models.
- `widgets/renderers/raster_region/raster_region_coloring_renderer.dart` adds the raster-region POC renderer with deterministic region-map lookup.
- `widgets/renderers/raster_region/raster_region_hit_tester.dart` maps canvas taps to image pixels and region IDs in O(1)-style lookup.
- `widgets/renderers/happy_cat_renderer.dart` remains as fallback sample renderer.
- `widgets/color_palette.dart` provides a 24-color palette with a clear selected state.
- `widgets/coloring_toolbar.dart` provides undo, redo, and clear actions.

## Distinction Between Implemented And Planned Architecture

### Implemented
- Feature-first Flutter structure
- Global theme and router
- Riverpod-based coloring state with explicit loading lifecycle
- Action-based undo/redo history
- Repository abstraction for category and page loading
- Renderer contract with graceful region validation
- Real SVG renderer for multiple local pages with parser, validation, and hit testing
- Offline coloring baseline once content is available locally
- Local page-scoped session persistence for region-color progress
- Resume behavior across route navigation and app/controller recreation

### CK-002.4 Session Persistence
- Persistence boundary is separate from content boundary:
	- `ColoringPageRepository` manages catalog/content identity.
	- `ColoringSessionRepository` manages user-created local coloring progress.
- Sessions are keyed by stable `pageId`.
- Session payload stores:
	- `pageId`
	- `regionColors` as ARGB `int` values
	- `schemaVersion` (current: `1`)
	- `lastUpdatedAtEpochMs`
- `loadPageById` restore sequence:
	- load page content from `ColoringPageRepository`
	- build default region colors from page model
	- load local session by `pageId`
	- reconcile saved region IDs against current page region IDs
	- apply valid saved colors and enter ready state
- Restore semantics:
	- unknown saved region IDs are ignored
	- new page regions missing from saved session keep defaults
	- restored sessions start with empty undo/redo history
- Save semantics:
	- persist after fill, undo, and redo
	- clear resets visible colors and deletes persisted page session
	- persistence operations are asynchronous and serialized to avoid stale write ordering
- Failure semantics:
	- persistence read/write errors are non-fatal to child coloring flow
	- coloring remains usable in memory
	- content load failures remain fatal according to existing loading/error lifecycle

### CK-002.5 My Creations Composition
- `ColoringSessionRepository` now supports session listing through `getAllSessions`.
- `LocalColoringSessionRepository.getAllSessions` semantics:
	- enumerate only `coloring_session:` keys
	- skip malformed entries
	- skip unsupported schema entries
	- continue loading valid entries even when one entry is malformed
	- return deterministic ordering: newest `lastUpdatedAtEpochMs` first, then `pageId` ascending
- `lib/features/gallery/providers/my_creations_provider.dart` composes:
	- persisted sessions (`ColoringSessionRepository`)
	- page and category metadata (`ColoringPageRepository`)
	- derived child-facing progress (`colored regions / total regions`)
- `GalleryScreen` consumes `myCreationsProvider` and supports:
	- loading state
	- ready state
	- empty state with Home CTA
	- friendly error state with retry
- My Creations only includes pages with non-zero progress (`coloredRegionCount > 0`).

### CK-002.5 Progress Derivation Semantics
- Progress formula: `colored valid page regions / total page regions`.
- Region rules:
	- missing session value => uncolored
	- persisted value equal to region default => uncolored
	- persisted value different from region default => colored
	- unknown persisted region IDs => ignored
	- zero page regions => progress ratio `0`

	### CK-002.6 Polished Content Foundation
	- Lovely Kitten is added as a new Animals benchmark page using the same `SvgColoringRenderer` pipeline.
	- Happy Cat remains available as a simpler regression baseline.
	- CK-002.6 introduces explicit content-authoring constraints documented in `docs/features/CK-002.6-svg-authoring-guide.md`.
	- Validator hard failures focus on deterministic correctness issues:
		- duplicate IDs
		- missing/empty colorable IDs
		- unsupported geometry usage
		- unexpected transforms
		- path metadata/geometry invalidity
		- model/SVG mismatch
	- Validator warning diagnostics surface probable usability risks (small targets, overlap, compound/hole-leaning paths) without changing runtime behavior.

### CK-002.5 Origin-Aware Return Navigation
- Coloring route accepts optional query metadata:
	- `source`
	- `sourceCategoryId`
- Supported origins:
	- category catalog (`source=category` + `sourceCategoryId`)
	- My Creations (`source=my-creations`)
- `ColoringScreen` back destination resolution:
	- My Creations origin returns to My Creations
	- category origin returns to that category
	- missing/invalid origin falls back safely (page category when available, then Home)
- CK-002.4 restore behavior remains in `ColoringController`; My Creations does not implement restore logic.

### CK-002.5 Refresh Semantics
- My Creations progress refreshes when returning from Coloring by route re-entry and provider recomputation.
- Clearing a page in Coloring still deletes the persisted session, so the page disappears from My Creations on return.

### Planned
- Expanded coloring content library
- Saved artwork storage and richer parent-facing progress features
- Firebase-backed account and content services
- AI content generation pipeline
- Purchase and subscription infrastructure

### CK-002.6 Phase 2E RasterRegion POC
- `ColoringRendererType` now supports both `svg` and `rasterRegion`.
- Existing `ColoringController`, undo/redo action history, and `ColoringSession` persistence remain renderer-agnostic.
- Raster page metadata is represented by `RasterRegionMetadata` on `ColoringPage` and includes:
	- `regionMapAssetPath`
	- `contentVersion`
	- `imageWidth`
	- `imageHeight`
	- deterministic `regionMapEntries` mapping encoded RGBA to stable `region-*` IDs
	- optional `metadataAssetPath` for provenance
- Raster rendering stack is:
	- dynamic color layer (derived from region map + current `regionColors`)
	- original line-art raster image on top (unchanged)
- Tap flow is:
	- tap location in canvas coordinates
	- map to raster pixel coordinates with letterbox-safe math
	- sample region-map RGBA
	- decode deterministic region ID
	- dispatch existing `fillRegion(regionId)` action
- Phase 2E uses the approved `CHILDREN_DETAILED` profile output for runtime POC and keeps `CHILDREN_SIMPLE` and weighted experiments as non-primary alternatives.
- SVG Lovely Kitten remains intact as the known-working comparison path.

### CK-002.6 Phase 2F Part 1 Child-Friendly Raster Content Workflow
- New child-friendly raster pages must follow `docs/content/color-kingdom-childrens-artwork-spec.md` before segmentation.
- Production artwork policy is AI generation plus Human QA plus AI regeneration/refinement, not routine manual repair or vectorization.
- Human QA gate #1 is artistic plus topology approval of the raster master before segmentation.
- Approved raster masters enter segmentation unchanged.
- Part 1 scope ends at Human QA artifact review for CHILDREN_DETAILED outputs.
- Runtime integration is explicitly deferred until Human QA approval.
- MASTER remains topology truth for accepted enclosed regions.
- CHILDREN_DETAILED is preservation-oriented and should remain close to MASTER, excluding only clear artifact/noise components.
- Tap target and related geometry metrics are retained for diagnostics, but tap target alone is not a hard exclusion in CHILDREN_DETAILED because zoom is available.
- MASTER region preservation remains mandatory for future alternate profiles.
- Phase 2F canonical QA artifacts are `regions_master_qa_fullcolor.png`, `regions_children_detailed_qa_fullcolor.png`, `master_vs_children_detailed_coverage.png`, `master_vs_children_detailed_coverage_labeled.png`, and `regions_children_detailed_exclusions.png`.
- Approved baseline success does not require vectorization, manual SVG region authoring, manual stable IDs, or manual region drawing.
- CHILDREN_SIMPLE remains the place for optional stronger simplification in the future.

### CK-002.6 Phase 2F Part 2 Cheerful Panda Runtime Integration
- Cheerful Panda is integrated as a real Animals raster page with stable page id `cheerful-baby-panda`.
- Runtime artifacts are generated by the generalized raster export pipeline and include:
	- `line_art_foreground.png`
	- `region_map.png`
	- `region_fill_map.png`
	- `metadata_children_detailed.json`
- Runtime metadata preserves deterministic `region-*` identities and maps all approved `CHILDREN_DETAILED` regions.
- Raster rendering remains data-driven through `ColoringRendererType.rasterRegion` and does not add page-id-specific renderer switches.
- Logical hit testing continues to use `region_map.png`, while visual fill coverage uses `region_fill_map.png` under the existing halo-safe strategy.

### CK-002.4 State Semantics
- Coloring region colors are persisted locally per page ID.
- Opening a page restores saved region colors when available and valid.
- Undo/redo history remains in-memory only and resets on restore/restart.
- Page sessions remain isolated by stable page identity.

### SVG Asset Conventions In Use
- Colorable regions use unique SVG IDs and `data-role="colorable"`.
- Static elements use `data-role="static"`.
- Optional human-readable names use `data-region-name`.
- Renderer validates region ID mapping in both directions:
	- every model region exists in SVG
	- every SVG colorable region exists in model
- Duplicate IDs and metadata issues are surfaced as diagnostic errors without crashing.
- CK-002.6 content targets path-only assets with `viewBox="0 0 512 512"` and avoids relying on unsupported geometry and transforms.

## Architectural Guidelines
- Keep feature logic close to the feature.
- Prefer small controllers and immutable state.
- Preserve the current baseline while extending the app.
- Document future architectural shifts before implementing them.
