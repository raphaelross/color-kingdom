# Architecture

## Architecture Summary
Color Kingdom currently uses a feature-first Flutter architecture with a shared app shell, centralized routing, a global theme, and feature-local state management for coloring.

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
- Home routes into category, gallery, and parent zone placeholders.

### Feature Structure
- `lib/features/home/` owns the home experience and reusable category card widget.
- `lib/features/coloring/` owns the current coloring baseline.
- `lib/features/categories/`, `gallery/`, `parent/`, and `settings/` contain placeholder screens for planned sections.
- `lib/shared/` exists for future reusable widgets and providers.

### Coloring Engine Baseline
The current coloring implementation now uses a production-ready renderer-independent foundation with an SVG renderer for Happy Cat.

Current coloring pieces:
- `models/coloring_page.dart` defines `ColoringPage` and `ColoringRegion`.
- `models/coloring_state.dart` defines loading/ready/error state plus action-based undo/redo history entries.
- `data/sample_coloring_pages.dart` defines a single Happy Cat sample page.
- `repositories/coloring_page_repository.dart` defines the page-source abstraction.
- `repositories/local_coloring_page_repository.dart` provides the current in-memory Happy Cat source.
- `providers/coloring_provider.dart` manages loading state, selected color, fills, undo, redo, clear, and page selection.
- `screens/coloring_screen.dart` composes toolbar, canvas, and palette.
- `widgets/coloring_renderer.dart` defines the renderer contract and region validation.
- `widgets/coloring_renderer_registry.dart` resolves a renderer for a page.
- `widgets/coloring_canvas.dart` hosts zoom/pan, runs renderer/page validation, and delegates drawing to a renderer.
- `widgets/renderers/svg/svg_coloring_renderer.dart` loads, validates, caches, and renders SVG coloring pages.
- `widgets/renderers/svg/svg_coloring_parser.dart` parses SVG assets and validates colorable region IDs.
- `widgets/renderers/svg/svg_region_hit_tester.dart` maps taps into SVG coordinates and resolves region hits.
- `widgets/renderers/svg/svg_coloring_models.dart` contains SVG renderer-specific internal models.
- `widgets/renderers/happy_cat_renderer.dart` remains as fallback sample renderer.
- `widgets/color_palette.dart` provides a 24-color palette with a clear selected state.
- `widgets/coloring_toolbar.dart` provides undo, redo, and clear actions.

## Distinction Between Implemented And Planned Architecture

### Implemented
- Feature-first Flutter structure
- Global theme and router
- Riverpod-based coloring state with explicit loading lifecycle
- Action-based undo/redo history
- Repository abstraction for page loading
- Renderer contract with graceful region validation
- Real SVG renderer for Happy Cat with parser, validation, and hit testing
- Offline coloring baseline once content is available locally

### Planned
- Expanded coloring content library
- Persistent user progress and artwork storage
- Firebase-backed account and content services
- AI content generation pipeline
- Purchase and subscription infrastructure

### SVG Asset Conventions In Use
- Colorable regions use unique SVG IDs and `data-role="colorable"`.
- Static elements use `data-role="static"`.
- Optional human-readable names use `data-region-name`.
- Renderer validates region ID mapping in both directions:
	- every model region exists in SVG
	- every SVG colorable region exists in model
- Duplicate IDs and metadata issues are surfaced as diagnostic errors without crashing.

## Architectural Guidelines
- Keep feature logic close to the feature.
- Prefer small controllers and immutable state.
- Preserve the current baseline while extending the app.
- Document future architectural shifts before implementing them.
