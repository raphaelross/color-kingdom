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
The current coloring implementation is intentionally simple and uses a sample page model with named regions, Riverpod state, and a renderer-independent foundation.

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
- `widgets/renderers/happy_cat_renderer.dart` renders the current sample page.
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
- Placeholder sample-page renderer
- Offline coloring baseline once content is available locally

### Planned
- SVG-based named-region asset pipeline
- Expanded coloring content library
- Persistent user progress and artwork storage
- Firebase-backed account and content services
- AI content generation pipeline
- Purchase and subscription infrastructure

## Architectural Guidelines
- Keep feature logic close to the feature.
- Prefer small controllers and immutable state.
- Preserve the current baseline while extending the app.
- Document future architectural shifts before implementing them.
