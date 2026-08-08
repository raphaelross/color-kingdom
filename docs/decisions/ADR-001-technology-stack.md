# ADR-001: Technology Stack

## Status
Accepted.

## Context
Color Kingdom is a child-focused coloring app that needs to run on iOS, Android, and optionally web, while staying maintainable as the feature set grows.

## Decision
Use Flutter for the cross-platform app, Firebase for backend services, Riverpod for feature state, and go_router for navigation.

## Rationale

### Flutter
- Single codebase for mobile and web.
- Strong UI control for kid-friendly interactions.
- Good fit for custom drawing, gesture handling, and responsive layouts.

### Firebase
- Provides authentication, Firestore, Cloud Storage, analytics, and notifications in a managed stack.
- Reduces backend setup overhead for an early-stage product.
- Supports content-driven features and future parental accounts.

### Riverpod
- Clear state ownership for feature controllers.
- Easier testing than ad hoc mutable state.
- Fits the app's feature-first structure.

### go_router
- Named routes keep navigation explicit and scalable.
- Central route definitions reduce coupling.
- Supports placeholders now and full screens later without rewriting navigation.

### Supporting Packages
- Google Fonts for a warm kid-friendly visual style.
- flutter_svg for the future SVG asset pipeline.
- shared_preferences and path_provider for local persistence support.
- image_gallery_saver_plus and uuid for artwork and asset workflows.

## Consequences
- The app can grow into a content platform without changing the foundation.
- Backend features remain optional and can be introduced incrementally.
- The codebase should stay disciplined about dependencies and architecture changes.
