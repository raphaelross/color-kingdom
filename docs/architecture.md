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
The current coloring implementation is intentionally simple and uses a sample page model with named regions and Riverpod state.

Current coloring pieces:
- `models/coloring_page.dart` defines `ColoringPage`, `ColoringRegion`, and `ColoringPageState`.
- `data/sample_coloring_pages.dart` defines a single Happy Cat sample page.
- `providers/coloring_provider.dart` manages selected color, fills, undo, redo, clear, and page selection.
- `screens/coloring_screen.dart` composes toolbar, canvas, and palette.
- `widgets/coloring_canvas.dart` renders the sample page and supports tap-to-fill plus zoom and pan.
- `widgets/color_palette.dart` provides a 24-color palette with a clear selected state.
- `widgets/coloring_toolbar.dart` provides undo, redo, and clear actions.

## Distinction Between Implemented And Planned Architecture

### Implemented
- Feature-first Flutter structure
- Global theme and router
- Riverpod-based coloring state
- Placeholder sample-page coloring engine
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
